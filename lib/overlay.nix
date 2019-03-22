self: super:

let
  inherit (super) callPackage;
  pkgs = self;
  preludeArgsPath = "${builtins.getEnv "XDG_RUNTIME_DIR"}/nix-prefetch/prelude-args.nix";
  preludeArgsGiven = builtins.pathExists preludeArgsPath;
  preludeArgs = if preludeArgsGiven then import preludeArgsPath else {
    fetcher = throw "Unknown fetcher.";
    forceHTTPS = false;
  };

in with import ./prelude.nix preludeArgs;

builtinsOverlay // {
  hello_rs = callPackage (if pathExists ../../contrib
    then ../../contrib/hello_rs # lib/nix-prefetch
    else    ../contrib/hello_rs # lib
  ) { };
}

// optionalAttrs preludeArgsGiven (let
  wrapInsecureArgBin = pkg: name: insecureArg: pkgs.buildEnv {
    name = "secure-${name}";
    paths = [
      pkg
      (hiPrio (pkgs.writeScriptBin name ''
        #!${pkgs.bash}/bin/bash
        args=()
        for arg in "$@"; do
          [[ $arg != ${insecureArg} ]] && args+=( "$arg" )
        done
        ${pkg}/bin/${name} "''${args[@]}"
      ''))
    ];
  };

  curlFetcher = fetcher: setFunctionArgs (args: fetcher (args // {
    curlOpts = (args.curlOpts or "") + " --no-insecure --cacert ${cacert}/etc/ssl/certs/ca-bundle.crt ";
  })) (functionArgs fetcher);

  unsafeFetcher = name: reason: throw "The fetcher ${name} is deemed unsafe: ${reason}.";

  # In order to overlay fetchers we first need to know what attributes in the packages attribute set are actually fetchers.
  # We cannot just assume any function is a fetcher function, because the function might be needed in order to construct
  # the expression being prefetched, so it would never reach the actual fetcher call.
  # We can only check for the name, if we were to check whether the value held a function,
  # it would lead to infinite recursion, because fetcher built on top of other fetchers
  # would be referring to their final versions, for which the list of top level fetchers is needed.
  topLevelFetchers = filter (name: isFetcher name id) (attrNames super);

  # It is used to secure fetchurl, bit it and its dependencies are in turn defined by fetchurl,
  # so we need to get a hold of an unaltered version of the package.
  cacert = (import self.path { overlays = []; }).cacert;

  mirrorsPkgs =
    let
      mirrorsPath = self.path + /pkgs/build-support/fetchurl/mirrors.nix;
      whitelist = map (path: self.path + path) [
        /pkgs/build-support/fetchurl
        /pkgs/build-support/fetchurl/boot.nix
        /pkgs/stdenv
        /pkgs/stdenv/linux
        /pkgs/top-level
        /pkgs/top-level/all-packages.nix
        /pkgs/top-level/impure.nix
        /pkgs/top-level/stage.nix
      ];
      customImport = scopedImport {
        import = path:
          if path == mirrorsPath then mapAttrs (_: map toHTTPS) (import mirrorsPath)
          else if elem path whitelist then customImport path
          else import path;
      };
    in customImport self.path { overlays = []; };

  mirrorsSuperPkgs = super // optionalAttrs preludeArgs.forceHTTPS {
    inherit (mirrorsPkgs) fetchurlBoot fetchurl;
  };

  fetcherSuperPkgs = mirrorsSuperPkgs // builtinsOverlay // genAttrs [ "fetchipfs" "fetchurl" ] (name: curlFetcher mirrorsSuperPkgs.${name});

  fetchers = primitiveFetchers ++ topLevelFetchers ++ optional (fetcher.type or null == "attr") fetcher.name;

in genFetcherOverlay fetcherSuperPkgs fetchers // {
  bazaar = wrapInsecureArgBin super.bazaar "bzr" "-Ossl.cert_reqs=none";
  mercurial = wrapInsecureArgBin super.mercurial "hg" "--insecure";
  subversion = wrapInsecureArgBin super.mercurial "svn" "--trust-server-cert";

  fetchs3 = unsafeFetcher "fetchs3" "the secret access key and session token will be stored in the Nix store";
  fetchsvnssh = unsafeFetcher "fetchsvnssh" "the SSH user and password will be stored in the Nix store";

  # fetchcvs, fetchegg (no HTTPS support it seems)
  # fetchfossil (does not support HTTPS anyways, it needs to be linked to openssl for that: https://www.fossil-scm.org/xfer/doc/trunk/www/ssl.wiki)
  # fetchmtn ?
})
