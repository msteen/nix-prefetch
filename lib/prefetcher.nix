{ prelude, pkgs, pkg, fetcher, fetcherArgs, hashAlgo, hash, fetchURL, forceHTTPS }@orig:

with prelude;

let
  isBuiltinFetcher = hasPrefix "builtins." fetcher.name;
  fetcherFunctionArgs = functionArgs fetcher;

  fetcherArgs = mapAttrs (_: value: toExprFun value pkgs) orig.fetcherArgs;

  givenHashAlgos = intersectLists (attrNames fetcherArgs) hashAlgos;

  hashAlgo = maybeNull orig.hashAlgo (
    if orig.hash != null then let hashLength = stringLength hash; in findFirst (hashAlgo: hashAlgo != null)
      (throw "No hash algorithm encoding could be found that matches the length ${toString hashLength} of hash '${hash}'.")
      (mapAttrsToList (encoding: { regex, lengths }:
        findFirst (name: lengths.${name} == hashLength && builtins.match regex hash != null) null (attrNames lengths)
      ) hashEncodings)
    else if length givenHashAlgos == 1 then head givenHashAlgos
    else "sha256");

  hash =
    if orig.hash != null then
      if givenHashAlgos == [] then orig.hash
      else throw "No hashes should be given as fetcher arguments when an explicit hash has been given, yet the following were given: ${toAndList givenHashAlgos}."
    else if givenHashAlgos == [] then
      if fetcher.args ? ${hashAlgo} then fetcher.args.${hashAlgo}
      else probablyWrongHashes.${hashAlgo}
    else if givenHashAlgos == [ hashAlgo ] then fetcherArgs.${hashAlgo}
    else if length givenHashAlgos == 1 then throw "The ${head givenHashAlgos} hash given as a fetcher argument did not match the expected hash algorithm ${hashAlgo}."
    else throw "Only hashes of one algorithm are allowed, yet the following were given: ${toAndList givenHashAlgos}.";

  checkHash = orig.hash != null || givenHashAlgos == [ hashAlgo ];

  hashSupport = !isBuiltinFetcher || fetcherFunctionArgs ? hash;

  fetcherHashArg =
    let
      key = if hashSupport then "hash" else hashAlgo;
    in
    singleAttr key hash;

  # https://stackoverflow.com/questions/28666357/git-how-to-get-default-branch/54204231#54204231
  gitHEAD = pkgs.writeScript "git-head.sh" ''
    #!${pkgs.bash}/bin/bash
    printf '"%s"' "$(${pkgs.git}/bin/git ls-remote "$1" HEAD | ${pkgs.gawk}/bin/awk '{ print $1 }')"
  '';

  fetcherRevArg = url: { rev = exec [ gitHEAD url ]; };

  prefetcherArgs =
    let args = removeAttrs fetcher.args (hashAlgos ++ [ "hash" ]) // fetcherArgs // fetcherHashArg;
    in args
    // optionalAttrs (fetcherFunctionArgs ? rev && args.rev or "" == "") (
      if fetcher.name == "fetchFromGitHub" && args ? owner && args ? repo then fetcherRevArg (fetcher (prefetcherArgs // { fetchSubmodules = true; })).url
      else if args ? url && hasSuffix ".git" args.url then fetcherRevArg args.url
      else {})
    // optionalAttrs (forceHTTPS && args ? url) { url = toHTTPS args.url; }
    // optionalAttrs (forceHTTPS && args ? urls) { urls = map toHTTPS args.urls; };

  urls =
    let src = fetcher prefetcherArgs;
    in if !isBuiltinFetcher && src ? urls then src.urls
    else if !isBuiltinFetcher && src ? url then [ src.url ]
    else if prefetcherArgs ? url then [ prefetcherArgs.url ]
    else [];

  prefetcher =
    let f =
      if !fetchURL then fetcher // { args = prefetcherArgs; }
      else if !isBuiltinFetcher then pkgs.fetchurl.__fetcher // {
        args =
          if urls != [] then { url = head urls; } // optionalAttr prefetcherArgs "name" // fetcherHashArg
          else throw "The fetcher ${fetcher.name} does not define any URLs.";
      }
      else throw "The --fetchurl option does not work with builtin fetchers.";
    in f // { drv = f f.args; };

  log = let toPrettyCode = x: let s = toPretty x; in replaceStrings [ "\n" ] [ "\n>   " ] s; in ''
    The ${if pkg != null then "package ${pkg.name} will be fetched" else "fetcher will be called"} as follows:
    > ${if hasPrefix "/" prefetcher.name then "import ${prefetcher.name}" else prefetcher.name} ${if prefetcher.args == {} then "{}" else ''
    {
    ${lines' (mapAttrsToList (name: value: ">   ${name} = ${toPrettyCode value};") prefetcher.args)}
    > }''}

  '';

  src = prefetcher.drv;

  wrongSrc = if src.outputHash != probablyWrongHashes.${hashAlgo}
    then src.overrideAttrs (const { outputHash = probablyWrongHashes.${hashAlgo}; })
    else src;

  json = recursiveUpdate {
    bash_vars = mapAttrs (const toString) {
      fetcher = prefetcher.name;
      hash_algo = hashAlgo;
      expected_hash = hash;
      actual_hash_size = hashEncodings.base32.lengths.${hashAlgo};
      check_hash = checkHash;
      hash_support = hashSupport;
    };
    fetcher_args = prefetcher.args;
    inherit urls log;
  } (optionalAttrs (!isBuiltinFetcher) {
    bash_vars = mapAttrs (const toString) {
      drv_path = src.drvPath;
      wrong_drv_path = wrongSrc.drvPath;
      output = src.out;
    };
  });

in { inherit fetcherArgs hashAlgo hash prefetcher json; }
