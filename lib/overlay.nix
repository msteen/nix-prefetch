self: super:

let
  inherit (super) callPackage;
  pkgs = self;

in with import ./prelude.nix;

{
  builtins = customBuiltins;

  # The builtin is also available outside of `builtins`.
  inherit (customBuiltins) fetchTarball;

  hello_rs = callPackage ../contrib/hello_rs { };
}

// optionalAttrs fetcherDefined (let
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
  topLevelFetchers = filter (name: isFetcher name) (attrNames super);

  # It is used to secure fetchurl, bit it and its dependencies are in turn defined by fetchurl,
  # so we need to get a hold of an unaltered version of the package.
  cacert = (import super.path { overlays = []; }).cacert;

  fetcherSuperPkgs = super // genAttrs [ "fetchipfs" "fetchurl" ] (name: curlFetcher super.${name});

in genFetcherOverlay fetcherSuperPkgs (topLevelFetchers ++ optional (fetcher.type or null == "attr") fetcher.name) // {
  bazaar = wrapInsecureArgBin super.bazaar "bzr" "-Ossl.cert_reqs=none";
  mercurial = wrapInsecureArgBin super.mercurial "hg" "--insecure";
  subversion = wrapInsecureArgBin super.mercurial "svn" "--trust-server-cert";

  fetchs3 = unsafeFetcher "fetchs3" "the secret access key and session token will be stored in the Nix store";
  fetchsvnssh = unsafeFetcher "fetchsvnssh" "the SSH user and password will be stored in the Nix store";

  # fetchcvs, fetchegg (no HTTPS support it seems)
  # fetchfossil (does not support HTTPS anyways, it needs to be linked to openssl for that: https://www.fossil-scm.org/xfer/doc/trunk/www/ssl.wiki)
  # fetchmtn ?
  # fetchs3 ?
})
