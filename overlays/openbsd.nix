final: prev:
let
  # Add unversioned .so names so linker and configure probes find OpenBSD libraries.
  withLinkerName =
    package: name:
    if prev.stdenv.hostPlatform.isOpenBSD then
      package.overrideAttrs (old: {
        postInstall =
          (old.postInstall or "")
          + "\n"
          + ''
            libraries=("$out/lib/${name}.so."*)
            (( ''${#libraries[@]} == 1 ))
            ln -sfn "''${libraries[0]##*/}" "$out/lib/${name}.so"
          '';
      })
    else
      package;

  # Remove once the pin includes https://github.com/NixOS/nixpkgs/pull/552510.
  staticPie =
    stdenv:
    if stdenv.hostPlatform.isOpenBSD then
      prev.stdenvAdapters.overrideMkDerivationArgs (
        args:
        if args ? NIX_CFLAGS_LINK then
          { NIX_CFLAGS_LINK = toString args.NIX_CFLAGS_LINK + " -pie"; }
        else
          {
            env = (args.env or { }) // {
              NIX_CFLAGS_LINK = toString (args.env.NIX_CFLAGS_LINK or "") + " -pie";
            };
          }
      ) stdenv
    else
      stdenv;
in
{
  stdenvAdapters = prev.stdenvAdapters // {
    makeStatic = stdenv: staticPie (prev.stdenvAdapters.makeStatic stdenv);
    makeStaticBinaries = stdenv: staticPie (prev.stdenvAdapters.makeStaticBinaries stdenv);
  };

  freebsd =
    if prev.stdenv.hostPlatform.isLinux then
      prev.freebsd
      // {
        # FreeBSD 15 makefs emits UFS1 images that OpenBSD 7.9 cannot remount
        # read-write. FreeBSD 14.2 is the newest packaged compatible release.
        makefs = (prev.freebsd.override { branch = "release/14.2.0"; }).makefs;
        # TODO(nixpkgs): upstream an explicit OpenBSD disklabel mode.
        mkimg = prev.freebsd.mkimg.overrideAttrs (old: {
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

  # TODO(nixpkgs): validate and upstream the remaining cross-build fixes.
  bzip2 = withLinkerName prev.bzip2 "libbz2";
  expat = withLinkerName prev.expat "libexpat";
  xz = withLinkerName prev.xz "liblzma";

  cmocka =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.cmocka.overrideAttrs (old: {
        doCheck = false;
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DWITH_EXAMPLES=OFF" ];
      })
    else
      prev.cmocka;

  curl =
    if prev.stdenv.hostPlatform.isOpenBSD then
      withLinkerName (prev.curl.override {
        gssSupport = false;
        http3Support = false;
        idnSupport = false;
        pslSupport = false;
      }) "libcurl"
    else
      prev.curl;

  gawk =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.gawk.overrideAttrs (old: {
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE_x86_64_unknown_openbsd =
            (old.env.NIX_CFLAGS_COMPILE_x86_64_unknown_openbsd or "") + " -D_BSD_SOURCE";
        };
      })
    else
      prev.gawk;

  gzip =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.gzip.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [ "gl_cv_func_fflush_stdin=yes" ];
      })
    else
      prev.gzip;

  gettext =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.gettext.overrideAttrs (old: {
        preInstall = (old.preInstall or "") + ''
          intlLibraries=(gettext-runtime/intl/.libs/libintl.so.*)
          textstyleLibraries=(libtextstyle/lib/.libs/libtextstyle.so.*)
          gettextlibLibraries=(gettext-tools/gnulib-lib/.libs/libgettextlib-*.so)
          gettextsrcLibraries=(gettext-tools/src/.libs/libgettextsrc-*.so)
          (( ''${#intlLibraries[@]} == 1 ))
          (( ''${#textstyleLibraries[@]} == 1 ))
          (( ''${#gettextlibLibraries[@]} == 1 ))
          (( ''${#gettextsrcLibraries[@]} == 1 ))
          mkdir -p "$out/lib"
          ln -s "$PWD/''${intlLibraries[0]}" "$out/lib/libintl.so"
          ln -s "$PWD/''${textstyleLibraries[0]}" "$out/lib/libtextstyle.so"
          ln -s "$PWD/''${gettextlibLibraries[0]}" "$out/lib/libgettextlib.so"
          ln -s "$PWD/''${gettextsrcLibraries[0]}" "$out/lib/libgettextsrc.so"
        '';
        postInstall = (old.postInstall or "") + ''
          pushd "$out/lib"
          for library in intl textstyle gettextlib gettextsrc; do
            rm "lib$library.so"
            versionedLibraries=("lib$library"*.so*)
            (( ''${#versionedLibraries[@]} == 1 ))
            ln -sfn "''${versionedLibraries[0]}" "lib$library.so"
          done
          popd
        '';
      })
    else
      prev.gettext;

  boehmgc =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.boehmgc.overrideAttrs (old: {
        preInstall = (old.preInstall or "") + ''
          gcLibraries=(.libs/libgc.so.*)
          (( ''${#gcLibraries[@]} == 1 ))
          ln -s "''${gcLibraries[0]##*/}" .libs/libgc.so
          mkdir -p "$out/lib"
          ln -s "$PWD/''${gcLibraries[0]}" "$out/lib/libgc.so"
        '';
        postInstall = (old.postInstall or "") + ''
          pushd "$out/lib"
          for library in gc gccpp gctba cord; do
            versionedLibraries=("lib$library.so."*)
            (( ''${#versionedLibraries[@]} == 1 ))
            ln -sfn "''${versionedLibraries[0]}" "lib$library.so"
          done
          popd
        '';
      })
    else
      prev.boehmgc;

  libiconv =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.libiconv.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          pushd "$out/lib"
          iconvLibraries=(libiconv.so.*)
          charsetLibraries=(libcharset.so.*)
          (( ''${#iconvLibraries[@]} == 1 ))
          (( ''${#charsetLibraries[@]} == 1 ))
          ln -s "''${iconvLibraries[0]}" libiconv.so
          ln -s "''${charsetLibraries[0]}" libcharset.so
          popd
        '';
      })
    else
      prev.libiconv;

  libarchive =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.libarchive.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [
          final.libiconv
          final.expat
        ];
        preConfigure = (old.preConfigure or "") + ''
          export LIBS="-Wl,-liconv -Wl,-lbz2 -Wl,-lexpat -Wl,-llzma -Wl,-lc"
        '';
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--without-xml2"
        ];
      })
    else
      prev.libarchive;

  libpng =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.libpng.overrideAttrs (old: {
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE_x86_64_unknown_openbsd =
            (old.env.NIX_CFLAGS_COMPILE_x86_64_unknown_openbsd or "") + " -D_BSD_SOURCE";
        };
      })
    else
      prev.libpng;

  libxml2 =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.libxml2.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ final.libiconv ];
        postInstall = (old.postInstall or "") + ''
          pushd "$out/lib"
          xmlLibraries=(libxml2.so.*)
          (( ''${#xmlLibraries[@]} == 1 ))
          ln -s "''${xmlLibraries[0]}" libxml2.so
          popd
        '';
      })
    else
      prev.libxml2;

  libxslt =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.libxslt.overrideAttrs (old: {
        preInstall = (old.preInstall or "") + ''
          xsltLibraries=(libxslt/.libs/libxslt.so.*)
          (( ''${#xsltLibraries[@]} == 1 ))
          mkdir -p "$out/lib"
          ln -s "$PWD/''${xsltLibraries[0]}" "$out/lib/libxslt.so"
        '';
        postInstall = (old.postInstall or "") + ''
          pushd "$out/lib"
          for library in xslt exslt; do
            versionedLibraries=("lib$library.so."*)
            (( ''${#versionedLibraries[@]} == 1 ))
            ln -sfn "''${versionedLibraries[0]}" "lib$library.so"
          done
          popd
        '';
      })
    else
      prev.libxslt;

  libxcrypt =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.libxcrypt.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [ "LIBS=-Wl,-lc" ];
      })
    else
      prev.libxcrypt;

  nix =
    if prev.stdenv.hostPlatform.isOpenBSD then
      (prev.nix.overrideScope (
        _nixFinal: nixPrev: {
          nix-store = (nixPrev.nix-store.override { withAWS = false; }).overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              ./nix-openbsd-builder-pipe.patch
              ./nix-openbsd-build-users.patch
            ];
          });
          nix-main = nixPrev.nix-main.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./nix-openbsd-atfork.patch ];
          });
          nix-util = nixPrev.nix-util.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace terminal.cc \
                --replace-fail '#  ifdef __APPLE__' \
                  '#  if defined(__APPLE__) || defined(__OpenBSD__)'
            '';
          });
          nix-cli = nixPrev.nix-cli.overrideAttrs (old: {
            env = (old.env or { }) // {
              NIX_CFLAGS_COMPILE_x86_64_unknown_openbsd =
                (old.env.NIX_CFLAGS_COMPILE_x86_64_unknown_openbsd or "")
                + " -DBOOST_STACKTRACE_GNU_SOURCE_NOT_REQUIRED";
            };
          });
        }
      ))
    else
      prev.nix;

  openssl =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.openssl.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [ "-Wl,-lc" ];
      })
    else
      prev.openssl;

  openssh =
    if prev.stdenv.hostPlatform.isOpenBSD then
      (prev.openssh.override { withLdns = false; }).overrideAttrs (old: {
        configureFlags =
          builtins.filter (flag: flag != "--with-libedit=yes") (old.configureFlags or [ ])
          ++ [ "--with-libedit=no" ];
      })
    else
      prev.openssh;

  oniguruma =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.oniguruma.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          pushd "$lib/lib"
          onigLibraries=(libonig.so.*)
          (( ''${#onigLibraries[@]} == 1 ))
          ln -s "''${onigLibraries[0]}" libonig.so
          popd
        '';
      })
    else
      prev.oniguruma;

  perl =
    if prev.stdenv.hostPlatform.isOpenBSD then
      let
        perl = (prev.perl.override { self = perl; }).overrideAttrs (old: {
          configureFlags = (old.configureFlags or [ ]) ++ [ "-Ud_clock_nanosleep" ];
        });
      in
      perl
    else
      prev.perl;

  perlPackages = if prev.stdenv.hostPlatform.isOpenBSD then final.perl.pkgs else prev.perlPackages;

  tcl =
    if prev.stdenv.hostPlatform.isOpenBSD then
      prev.tcl.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [ "tcl_cv_sys_version=OpenBSD-7.9" ];
        postPatch = (old.postPatch or "") + ''
          dollar='$'
          substituteInPlace unix/tcl.m4 unix/configure \
            --replace-fail \
              "$dollar{TCL_TRIM_DOTS}.so$dollar{SHLIB_VERSION}" \
              "$dollar{TCL_TRIM_DOTS}.so"
        '';
        postInstall = ''
          make install-private-headers
          ln -s "$out/lib/libtcl86.so" "$out/lib/libtcl.so"
        '';
      })
    else
      prev.tcl;

  openbsd = prev.openbsd.overrideScope (
    openbsdFinal: openbsdPrev: {
      # TODO(nixpkgs): upstream init and stat.
      init = openbsdFinal.callPackage (
        {
          lib,
          mkDerivation,
          runtimeShell,
        }:
        mkDerivation {
          path = "sbin/init";
          postPatch = ''
            substituteInPlace "$BSDSRCDIR/sbin/init/pathnames.h" \
              --replace-fail '#include <paths.h>' \
                $'#include <paths.h>\\n\\n#undef _PATH_BSHELL\\n#define _PATH_BSHELL "${runtimeShell}"'
            substituteInPlace "$BSDSRCDIR/sbin/init/init.c" \
              --replace-fail '	setenv("PATH", _PATH_STDPATH, 1);' ""
          '';
          meta = {
            mainProgram = "init";
            platforms = lib.platforms.openbsd;
          };
        }
      ) { };

      stat = openbsdFinal.mkDerivation { path = "usr.bin/stat"; };

      # Remove once the pin includes https://github.com/NixOS/nixpkgs/pull/552510.
      stand = openbsdPrev.stand.overrideAttrs (old: {
        patches = [
          ./openbsd-initpath.patch
          (prev.path + "/pkgs/os-specific/bsd/openbsd/pkgs/cmd-buff-size.patch")
        ];
        postPatch = (old.postPatch or "") + ''
          # These uninstalled host utilities require OpenBSD base libraries.
          substituteInPlace $BSDSRCDIR/sys/arch/amd64/stand/Makefile \
            --replace-fail 'SUBDIR+=rdboot vmboot' ""

          # Boot code is linked below lld's default image base.
          substituteInPlace $BSDSRCDIR/sys/arch/amd64/stand/{mbr,biosboot}/Makefile \
            --replace-fail '-Ttext 0' '-Ttext 0 --image-base=0'
          substituteInPlace $BSDSRCDIR/sys/arch/amd64/stand/{boot,cdboot,pxeboot}/Makefile \
            --replace-fail '-Ttext $(LINKADDR)' '-Ttext $(LINKADDR) --image-base=0'
          substituteInPlace $BSDSRCDIR/sys/arch/amd64/stand/cdbr/Makefile \
            --replace-fail '-Ttext ''${ORG}' '-Ttext ''${ORG} --image-base=0'

          # LLVM reads lld's ELF output; GNU objcopy converts it to EFI PE.
          substituteInPlace $BSDSRCDIR/sys/arch/amd64/stand/efiboot/Makefile.common \
            --replace-fail '    --target=''${OBJFMT} ''${PROG.so} ''${.TARGET}' \
              '    --input-target=''${INPUTFMT} --output-target=''${OBJFMT} --subsystem=efi-app ''${PROG.so}.elf ''${.TARGET}'
          sed -i '/^''${PROG}: ''${PROG.so}$/a\	''${LLVM_OBJCOPY} --output-target=''${INPUTFMT} ''${PROG.so} ''${PROG.so}.elf' \
            $BSDSRCDIR/sys/arch/amd64/stand/efiboot/Makefile.common
          substituteInPlace $BSDSRCDIR/sys/arch/amd64/stand/efiboot/bootx64/Makefile \
            --replace-fail 'OBJFMT=		efi-app-x86_64' \
              $'OBJFMT=\t\tpei-x86-64\nINPUTFMT=\telf64-x86-64'
          substituteInPlace $BSDSRCDIR/sys/arch/amd64/stand/efiboot/bootia32/Makefile \
            --replace-fail 'OBJFMT=		efi-app-ia32' \
              $'OBJFMT=\t\tpei-i386\nINPUTFMT=\telf32-i386'
        '';
        preBuild = (old.preBuild or "") + ''
          export OBJCOPY="${final.buildPackages.binutils-unwrapped-all-targets}/bin/${final.stdenv.cc.targetPrefix}objcopy"
          export LLVM_OBJCOPY="${final.buildPackages.llvmPackages.llvm}/bin/llvm-objcopy"
        '';
      });

      rc = openbsdPrev.rc.overrideAttrs (old: {
        # Remove once the pin includes https://github.com/NixOS/nixpkgs/pull/552510.
        patches = map (
          patch:
          if builtins.baseNameOf patch == "boot-phases.patch" then ./openbsd-boot-phases.patch else patch
        ) old.patches;
        # NixBSD runtime integration.
        postPatch = (old.postPatch or "") + ''
          substituteInPlace "$BSDSRCDIR/etc/rc" \
            --replace-fail 'stat -f "%Hr"' '${openbsdFinal.stat}/bin/stat -f "%Hr"' \
            --replace-fail 'stat -f "%Lr"' '${openbsdFinal.stat}/bin/stat -f "%Lr"' \
            --replace-fail 'stat -qf %Hr,%Lr' '${openbsdFinal.stat}/bin/stat -qf %Hr,%Lr' \
            --replace-fail 'proto icmp6' 'proto 58' \
            --replace-fail 'proto carp' 'proto 112'
          substituteInPlace "$BSDSRCDIR/etc/rc.d/rc.subr" \
            --replace-fail \
              'local _rcexec="su -fl -c ''${daemon_class} -s /bin/sh ''${daemon_user} -c"' \
              'local _rcexec="${final.runtimeShell} -c"' \
            --replace-fail '"$(id -R)"' '"$(${openbsdFinal.id}/bin/id -R)"' \
            --replace-fail '"$(id -u)"' '"$(${openbsdFinal.id}/bin/id -u)"'
        '';
      });

      sys = openbsdPrev.sys.overrideAttrs (old: {
        # init-path/-fret-clean: remove once the pin includes https://github.com/NixOS/nixpkgs/pull/552510.
        patches = [ ./openbsd-initpath.patch ];
        # Keep TMPFS enabled for NixBSD's /run/wrappers.
        postPatch = (old.postPatch or "") + ''
          find $BSDSRCDIR -name 'Makefile*' -exec sed -i 's/-fret-clean//g' {} +
          substituteInPlace "$BSDSRCDIR/sys/conf/GENERIC" \
            --replace-fail '#option		TMPFS' 'option		TMPFS'
        '';
      });
    }
  );
}
