# OpenBSD package prerequisites; prepare these for Nixpkgs separately.
final: prev:
let
  # Add unversioned .so names so linker and configure probes find OpenBSD libraries.
  withLinkerName =
    package: name:
    package.overrideAttrs (old: {
      postInstall =
        (old.postInstall or "")
        + "\n"
        + ''
          libraries=("$out/lib/${name}.so."*)
          (( ''${#libraries[@]} == 1 ))
          ln -sfn "''${libraries[0]##*/}" "$out/lib/${name}.so"
        '';
    });

in
prev.lib.optionalAttrs prev.stdenv.hostPlatform.isOpenBSD {
  # TODO(nixpkgs): validate and upstream the remaining cross-build fixes.
  bzip2 = withLinkerName prev.bzip2 "libbz2";
  expat = withLinkerName prev.expat "libexpat";
  xz = withLinkerName prev.xz "liblzma";

  cmocka = prev.cmocka.overrideAttrs (old: {
    doCheck = false;
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DWITH_EXAMPLES=OFF" ];
  });

  curl = withLinkerName (prev.curl.override {
    gssSupport = false;
    http3Support = false;
    idnSupport = false;
    pslSupport = false;
  }) "libcurl";

  gawk = prev.gawk.overrideAttrs (old: {
    env = (old.env or { }) // {
      NIX_CFLAGS_COMPILE_x86_64_unknown_openbsd =
        (old.env.NIX_CFLAGS_COMPILE_x86_64_unknown_openbsd or "") + " -D_BSD_SOURCE";
    };
  });

  gzip = prev.gzip.overrideAttrs (old: {
    configureFlags = (old.configureFlags or [ ]) ++ [ "gl_cv_func_fflush_stdin=yes" ];
  });

  fcron = prev.fcron.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      # OpenBSD also defines SO_PEERCRED; select fcron's getpeereid backend.
      substituteInPlace fcrondyn_svr.c \
        --replace-fail '#ifdef SO_PEERCRED' \
          '#if defined(SO_PEERCRED) && defined(SO_PASSCRED)'
    '';
  });

  gettext = prev.gettext.overrideAttrs (old: {
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
  });

  boehmgc = prev.boehmgc.overrideAttrs (old: {
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
  });

  libiconv = prev.libiconv.overrideAttrs (old: {
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
  });

  libpng = (withLinkerName prev.libpng "libpng16").overrideAttrs (old: {
    # pngcp requests POSIX APIs, but OpenBSD's sys/time.h also needs BSD types.
    env = (old.env or { }) // {
      NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -D_BSD_SOURCE";
    };
    postInstall = (old.postInstall or "") + ''
      ln -s libpng16.so "$out/lib/libpng.so"
    '';
  });

  libarchive = prev.libarchive.overrideAttrs (old: {
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
  });

  libxml2 = prev.libxml2.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ final.libiconv ];
    postInstall = (old.postInstall or "") + ''
      pushd "$out/lib"
      xmlLibraries=(libxml2.so.*)
      (( ''${#xmlLibraries[@]} == 1 ))
      ln -s "''${xmlLibraries[0]}" libxml2.so
      popd
    '';
  });

  libxslt = prev.libxslt.overrideAttrs (old: {
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
  });

  libxcrypt = prev.libxcrypt.overrideAttrs (old: {
    configureFlags = (old.configureFlags or [ ]) ++ [ "LIBS=-Wl,-lc" ];
  });

  openssl = prev.openssl.overrideAttrs (old: {
    configureFlags = (old.configureFlags or [ ]) ++ [ "-Wl,-lc" ];
  });

  openssh = (prev.openssh.override { withLdns = false; }).overrideAttrs (old: {
    configureFlags =
      builtins.filter (flag: flag != "--with-libedit=yes") (old.configureFlags or [ ])
      ++ [ "--with-libedit=no" ];
  });

  oniguruma = prev.oniguruma.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      pushd "$lib/lib"
      onigLibraries=(libonig.so.*)
      (( ''${#onigLibraries[@]} == 1 ))
      ln -s "''${onigLibraries[0]}" libonig.so
      popd
    '';
  });

  perl =
    let
      perl = (prev.perl.override { self = perl; }).overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [ "-Ud_clock_nanosleep" ];
      });
    in
    perl;

  perlPackages = final.perl.pkgs;

  vim = prev.vim.overrideAttrs (old: {
    # The cross-build defaults assume POSIX timers, which OpenBSD lacks.
    configureFlags =
      builtins.filter (flag: !prev.lib.hasPrefix "vim_cv_timer_create" flag) (old.configureFlags or [ ])
      ++ [
        "vim_cv_timer_create=no"
        "vim_cv_timer_create_with_lrt=no"
      ];
  });

  tcl = prev.tcl.overrideAttrs (old: {
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
  });
}
// {
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
                $'#include <paths.h>\n\n#undef _PATH_BSHELL\n#define _PATH_BSHELL "${runtimeShell}"'
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

      # TODO(nixpkgs): upstream getcap, used by rc.subr to select login classes.
      getcap = openbsdFinal.mkDerivation { path = "usr.bin/getcap"; };

      # TODO(nixpkgs): upstream the native password-changing utility.
      passwd = openbsdFinal.mkDerivation {
        path = "usr.bin/passwd";
        extraPaths = [ "usr.bin/chpass" ];
        buildInputs = [
          openbsdFinal.librpcsvc
          openbsdFinal.libutil
        ];
        postPatch = ''
          sed -i -e '/^BINMODE=/d' -e '/^DPADD/d' $BSDSRCDIR/usr.bin/passwd/Makefile
        '';
        meta.mainProgram = "passwd";
      };

    }
  );
}
