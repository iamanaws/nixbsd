# Nixpkgs #552510 is merged, but NixBSD's current pin predates it.
# Keep these isolated until a Nixpkgs update also passes FreeBSD validation.
final: prev:
let
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

  openbsd = prev.openbsd.overrideScope (
    openbsdFinal: openbsdPrev: {
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
      });
      sys = openbsdPrev.sys.overrideAttrs (old: {
        patches = [ ./openbsd-initpath.patch ];
        postPatch = (old.postPatch or "") + ''
          find $BSDSRCDIR -name 'Makefile*' -exec sed -i 's/-fret-clean//g' {} +
        '';
      });
    }
  );
}
