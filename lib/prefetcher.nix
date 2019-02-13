{ lib, pkgs, pkg, fetcher, fetcherArgs, hashAlgo, hash, fetchURL }@orig:

with lib;

let
  isBuiltinFetcher = hasPrefix "builtins." fetcher.name;

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

  fetcherHashArg = singleAttr hashAlgo hash;

  prefetcherArgs = removeAttrs fetcher.args hashAlgos // fetcherArgs // fetcherHashArg;

  urls =
    let src = fetcher.value prefetcherArgs;
    in if !isBuiltinFetcher && src ? urls then src.urls
    else if !isBuiltinFetcher && src ? url then [ src.url ]
    else if prefetcherArgs ? url then [ prefetcherArgs.url ]
    else [];

  prefetcher =
    if !fetchURL then fetcher // { args = prefetcherArgs; }
    else if !isBuiltinFetcher then {
      name = "fetchurl";
      value = pkgs.fetchurl;
      args =
        if urls != [] then { url = head urls; } // optionalAttr prefetcherArgs "name" // fetcherHashArg
        else throw "The fetcher ${fetcher.name} does not define any URLs.";
    }
    else throw "The fetchURL option does not work with builtin fetchers.";

  log = let toPrettyCode = x: let s = toPretty x; in replaceStrings [ "\n" ] [ "\n>   " ] s; in ''
    The ${if pkg != null then "package ${pkg.name} will be fetched" else "fetcher will be called"} as follows:
    > ${if hasPrefix "/" prefetcher.name then "import ${prefetcher.name}" else prefetcher.name} {
    ${lines' (mapAttrsToList (name: value: ">   ${name} = ${toPrettyCode value};") prefetcher.args)}
    > }

  '' + optionalString (urls != []) ''
    The following URLs will be fetched as part of the source:
    ${lines urls}
  '';

  src = with prefetcher; value args;

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
    };
    fetcher_args = prefetcher.args;
    inherit log;
  } (optionalAttrs (!isBuiltinFetcher) {
    bash_vars = mapAttrs (const toString) {
      drv_path = src.drvPath;
      wrong_drv_path = wrongSrc.drvPath;
      output = src.out;
    };
  });

in { inherit fetcherArgs hashAlgo hash prefetcher json; }
