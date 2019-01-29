orig:

let common = import ./common-expr.nix orig; in with common;

let
  isBuiltinFetcher = hasPrefix "builtins." fetcher.name;

  src = with fetcher; fun args;

  srcURLs = if isBuiltinFetcher then [] else sourceURLs src;

  log = writeLog common.log (optionalString (srcURLs != []) ''
    The following URLs will be fetched as part of the source:
    ${lines srcURLs}
  '');

  wrongSrc = if src.outputHash != probablyWrongHashes.${hashAlgo}
    then src.overrideAttrs (_: { outputHash = probablyWrongHashes.${hashAlgo}; })
    else src;

  diffFetcherArgs = args: filterAttrs (name: value: value != fetcher.oldArgs.${name}) (builtins.intersectAttrs fetcher.newArgs args)
    // fetcher.hashArgs; # The actual hash is only known after running this program, so we want to keep it regardless.

  addFetcherArgPositions = args: mapAttrs (name: value: {
    position = fetcher.origArgPositions.${name}
      or (throw "Cannot get position the position for fetcher argument '${name}', since it does not already exist in the fetcher call.");
    inherit value;
  }) args;

  json = recursiveUpdate {
    bash_vars = mapAttrs (const toString) {
      hash_algo = hashAlgo;
      expected_hash = hash;
      actual_hash_size = actualHashSize;
      check_hash = checkHash;
      fetcher = fetcher.name;
    };
    inherit log;
    output = applyIf (const orig.withPosition) addFetcherArgPositions (applyIf (const orig.diff) diffFetcherArgs fetcher.args);
  } (optionalAttrs (!isBuiltinFetcher) {
    bash_vars = mapAttrs (const toString) {
      wrong_drv_path = wrongSrc.drvPath;
      drv_path = src.drvPath;
      output = src.out;
    };
  });

in if isBuiltinFetcher
then seq (exec [ orig.writeFile orig.jsonFile (toJSON json) ]) wrongSrc.drvPath
else json
