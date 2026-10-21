final: prev:

prev.lib.composeManyExtensions [
  (import ./openbsd-backports.nix)
  (import ./openbsd-packages.nix)
  (import ./openbsd-nix.nix)
  (final: prev: {
    freebsd =
      if prev.stdenv.hostPlatform.isLinux then
        prev.freebsd
        // {
          # FreeBSD 15 makefs emits UFS1 images that OpenBSD 7.9 cannot remount
          # read-write. FreeBSD 14.2 is the newest packaged compatible release.
          makefs = (prev.freebsd.override { branch = "release/14.2.0"; }).makefs.overrideAttrs (old: {
            meta.platforms = old.meta.platforms ++ prev.lib.platforms.linux;
          });
          # TODO(nixpkgs): upstream an explicit OpenBSD disklabel mode.
          mkimg = prev.freebsd.mkimg.overrideAttrs (old: {
            meta.platforms = old.meta.platforms ++ prev.lib.platforms.linux;
            postPatch = (old.postPatch or "") + ''
              substituteInPlace "$BSDSRCDIR/usr.bin/mkimg/bsd.c" \
                --replace-fail \
                  'le32enc(&d->d_magic, BSD_MAGIC);' \
                  $'le32enc(&d->d_magic, BSD_MAGIC);\n\tle32enc(&d->d_type, DTYPE_SCSI);\n\t/* OpenBSD 7.9 only accepts v1 disklabels. */\n\tle32enc(&d->d_spare[0], 1U << 16);' \
                --replace-fail \
                  'le32enc(&dp->p_offset, part->block);' \
                  'le32enc(&dp->p_offset, part->block + relocation);'
              substituteInPlace "$BSDSRCDIR/usr.bin/mkimg/mkimg.c" \
                --replace-fail \
                  'uint32_t active_partition = 0;' \
                  $'uint32_t active_partition = 0;\nint32_t relocation = 0;' \
                --replace-fail \
                  $'\tfprintf(stderr, "\\t-s <scheme>\\n");' \
                  $'\tfprintf(stderr, "\\t-s <scheme>\\n");\n\tfprintf(stderr, "\\t-r <relocation>\\n");' \
                --replace-fail \
                  '"a:b:c:C:f:o:p:s:t:vyH:P:S:T:"' \
                  '"a:b:c:C:f:o:p:s:t:vyH:P:S:T:r:"' \
                --replace-fail \
                  $'\t\tcase LONGOPT_FORMATS:' \
                  $'\t\tcase \'r\':\n\t\t\trelocation = atoi(optarg);\n\t\t\tbreak;\n\t\tcase LONGOPT_FORMATS:'
              substituteInPlace "$BSDSRCDIR/usr.bin/mkimg/mkimg.h" \
                --replace-fail \
                  'extern uint32_t active_partition;' \
                  $'extern uint32_t active_partition;\nextern int32_t relocation;'
              substituteInPlace "$BSDSRCDIR/usr.bin/mkimg/scheme.h" \
                --replace-fail $'\tALIAS_NTFS,' \
                  $'\tALIAS_NTFS,\n\tALIAS_OPENBSD_DATA,'
              substituteInPlace "$BSDSRCDIR/usr.bin/mkimg/scheme.c" \
                --replace-fail $'\t{ "ntfs", ALIAS_NTFS },' \
                  $'\t{ "ntfs", ALIAS_NTFS },\n\t{ "openbsd-data", ALIAS_OPENBSD_DATA },'
              substituteInPlace "$BSDSRCDIR/usr.bin/mkimg/gpt.c" \
                --replace-fail \
                  'static mkimg_uuid_t gpt_uuid_mbr = GPT_ENT_TYPE_MBR;' \
                  $'static mkimg_uuid_t gpt_uuid_mbr = GPT_ENT_TYPE_MBR;\nstatic mkimg_uuid_t gpt_uuid_openbsd_data = GPT_ENT_TYPE_OPENBSD_DATA;' \
                --replace-fail \
                  $'    {\tALIAS_MBR, ALIAS_PTR2TYPE(&gpt_uuid_mbr) },' \
                  $'    {\tALIAS_MBR, ALIAS_PTR2TYPE(&gpt_uuid_mbr) },\n    {\tALIAS_OPENBSD_DATA, ALIAS_PTR2TYPE(&gpt_uuid_openbsd_data) },'
            '';
          });
        }
      else
        prev.freebsd;

    openbsd = prev.openbsd.overrideScope (
      openbsdFinal: openbsdPrev: {
        su = openbsdPrev.su.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            # Check wheel membership by name: NixBSD reserves gid 0 for root.
            substituteInPlace "$BSDSRCDIR/usr.bin/su/su.c" \
              --replace-fail 'getgrgid(0)' 'getgrnam("wheel")'
            # The auth helper symlinks into /run/wrappers, outside the unveiled directory.
            substituteInPlace "$BSDSRCDIR/usr.bin/su/su.c" \
              --replace-fail \
                'auth_verify(as, style, NULL, lc->lc_class, (char *)NULL);' \
                'if (unveil(_PATH_AUTHPROGDIR "/login_passwd", "x") == -1)
                     err(1, "unveil login_passwd");
                 auth_verify(as, style, NULL, lc->lc_class, (char *)NULL);'
          '';
        });

        rc = openbsdPrev.rc.overrideAttrs (old: {
          # NixBSD runtime integration.
          postPatch = (old.postPatch or "") + ''
            substituteInPlace "$BSDSRCDIR/etc/rc" \
              --replace-fail 'sh /etc/netstart' '${final.oksh}/bin/oksh /etc/netstart'
            substituteInPlace "$BSDSRCDIR/etc/rc.d/rc.subr" \
              --replace-fail \
                'local _rcexec="su -fl -c ''${daemon_class} -s /bin/sh ''${daemon_user} -c"' \
                'local _rcexec="${openbsdFinal.su}/bin/su -fl -c ''${daemon_class} -s ${final.runtimeShell} ''${daemon_user} -c"' \
              --replace-fail '"''${_set_monitor}; \' \
                '"''${_set_monitor}; ''${nixbsd_environment:-:}; \' \
              --replace-fail '"$(id -R)"' '"$(${openbsdFinal.id}/bin/id -R)"'
          '';
          # Install rc's network setup and the OpenBSD protocol aliases it uses.
          installPhase = old.installPhase + ''
            cp "$BSDSRCDIR"/etc/{netstart,protocols,services} "$out/etc/"
          '';
        });

        sys = openbsdPrev.sys.overrideAttrs (old: {
          # Keep TMPFS enabled for NixBSD's /run/wrappers.
          postPatch = (old.postPatch or "") + ''
            substituteInPlace "$BSDSRCDIR/sys/conf/GENERIC" \
              --replace-fail '#option		TMPFS' 'option		TMPFS'
          '';
        });
      }
    );
  })
] final prev
