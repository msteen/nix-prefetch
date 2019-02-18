self: super:

let prelude = import ./prelude.nix; in with prelude;

let
  # In order to overlay fetchers we first need to know what attributes in the packages attribute set are actually fetchers.
  # We cannot just assume any function is a fetcher function, because the function might be needed in order to construct
  # the expression being prefetched, so it would never reach the actual fetcher call.
  topLevelFetchers = filter (name: isFetcher name) (attrNames super);

  wrapSecureBin = pkg: name: arg: super.buildEnv {
    name = "secure-${name}";
    paths = [
      pkg
      (hiPrio (super.writeScriptBin name ''
        #!${super.bash}/bin/bash
        args=()
        for arg in "$@"; do
          [[ $arg != ${arg} ]] && args+=( "$arg" )
        done
        ${pkg}/bin/${name} "''${args[@]}"
      ''))
    ];
  };

in genFetcherOverlay super (topLevelFetchers ++ optional (fetcher.type or null == "attr") fetcher.name)
// import ./pkgs-extra.nix { inherit prelude; inherit (super) callPackage; }
// {
  bazaar = wrapSecureBin super.bazaar "bzr" "-Ossl.cert_reqs=none";
  mercurial = wrapSecureBin super.mercurial "hg" "--insecure";
  subversion = wrapSecureBin super.mercurial "svn" "--trust-server-cert";

  # fetchcvs, fetchegg (no HTTPS support it seems)
  # fetchdocker ?
  # fetchfossil (does not support HTTPS anyways, it needs to be linked to openssl for that: https://www.fossil-scm.org/xfer/doc/trunk/www/ssl.wiki)
  # fetchmtn ?
  # fetchs3 ?
  # fetchsvnssh "Pipe the "p" character into Subversion to force it to accept the server's certificate." ?
}
