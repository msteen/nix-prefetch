{ lib, nixpkgsPath, exprFun, index, fetcher, fetcherArgs, hashAlgo, hash, fetchURL, quiet, verbose, debug }@origArgs:

with lib;

# Trust-On-First-Use (TOFU) is a security model that will trust that, the response given by the non-yet-trusted endpoint,
# is correct on first use and will derive an identifier from it to check the trustworthiness of future requests to the endpoint.
# An well-known example of this is with SSH connections to hosts that are reporting a not-yet-known host key.
# In the context of Nixpkgs, TOFU can be applied to fixed-output derivation (like produced by fetchers) to supply it with an output hash.
# https://en.wikipedia.org/wiki/Trust_on_first_use

# To implement the TOFU security model for fixed-output derivations the output hash has to determined at first build.
# This can be achieved by first supplying the fixed-output derivation with a probably-wrong output hash,
# that forces the build to fail with a hash mismatch error, which contains in its error message the actual output hash.
let
  # The expression is defined as a function to allow us to bring the `pkgs` attribute of Nixpkgs into scope,
  # upon which the actual expression might be dependent.
  expr = exprFun pkgs;

  # If the index is undefined when it is actually needed, we choose to require to be explicit about it,
  # so instead of defaulting to 0, we throw an error.
  index = maybeNull origArgs.index (throw "no index has been given, which is necessary to choose one of the multiple sources");

  hashAlgo = maybeNull origArgs.hashAlgo (if hash == null then "sha256" else
    let
      hashLength = stringLength hash;
      algoWithLength = encLengths: foldrAttrs (name: value: algo: if value == hashLength then name else algo) null encLengths;
      base16Algo = algoWithLength hashLengths.base16;
      base32Algo = algoWithLength hashLengths.base32;
    in if base16Algo != null && base32Algo != null then if builtins.match "[0-9a-f]+" != null hash then base16Algo else base32Algo
    else if base16Algo != null then base16Algo
    else if base32Algo != null then base32Algo
    else throw "no hash algorithm encoding could be found that matches the length ${toString hashLength} of hash '${hash}'"
  );

  # The Nixpkgs path is a Nix expression that produces such a path,
  # so since it requires evaluation, we can only validate it within Nix.
  nixpkgsPath = let checkPath = origArgs.nixpkgsPath + /pkgs/top-level; in
    if pathExists checkPath then origArgs.nixpkgsPath
    else throw "invalid Nixpkgs path, could not find path '${toString checkPath}'";
  pkgs = let origPkgs = import nixpkgsPath { }; in
    if isNixpkgs origPkgs then origPkgs
    else throw "invalid Nixpkgs path, it did not evaluate to an attribute set with the expected attributes";

  # If we want to reuse the existing arguments passed to the fetcher, we have the following options available.
  # 1. Specify which fetcher is being used explicitly.
  # 2. Override all known fetchers of the package arguments.
  # 3. Overlay all known fetchers in the top level of Nixpkgs.
  # Besides option 3, option 1 also needs to use an overlay,
  # because there is no guarantee the given fetcher is listed in the package arguments.
  # We cannot simply overwrite the default overlays, because they might be used,
  # so we need to determine the default overlays and add to them our overlay for the fetchers.
  # Unfortunately there is no way to get the overlays after configuring a Nixpkgs with them,
  # so instead we use scoped imports to overwrite the default import definition in such a way
  # that instead of returning the Nix packages set, we have it return its own arguments.
  nixpkgsOverlays =
    let
      import = scopedImport {
        import = path: if path == nixpkgsPath + /pkgs/top-level
          then (args: args)
          else import path;
      };
      topLevelArgs = import nixpkgsPath { };
    in topLevelArgs.overlays;

  hashLengths = {
    base16 = {
      md5    = 32;
      sha1   = 40;
      sha256 = 64;
      sha512 = 128;
    };
    base32 = {
      md5    = 26;
      sha1   = 32;
      sha256 = 52;
      sha512 = 103;
    };
  };

  hashAlgos = attrNames hashLengths.base32;

  # The most obivous probably-wrong output hashes are zero valued output hashes, so they will be used.
  # The hashes are using base 32 encoding, because the actual output hash being reported in the hash mismatch error message
  # will also be using this encoding. For the purpose of having a probably-wrong output hash,
  # any other valid hash encoding would have been fine though.
  probablyWrongHashes = mapAttrs (_: length: repeatString length "0") hashLengths.base32;

  writeLog = optionals (!quiet);

  prefetched =
    if isFunction expr then prefetchedFetcher
    else if isPackage expr then prefetchedPackage
    else throw "the expression does not resolve to either fetcher function or package derivation";

  packageSource = pkg: if pkg ? srcs then elemAt pkg.srcs index else pkg.src;

  sourceURLs = src: if src ? urls then src.urls else if src ? url then [ src.url ] else [];

  # If the expression being prefetched is a call to a fetcher and fetcher arguments have been passed over the command line,
  # then we would like to reuse the original fetcher arguments and extend them with those that were passed.
  # The original arguments passed to the fetcher function will be lost when the expression containing the call gets evaluated,
  # instead we get the resulting fixed-output derivation, from which the original arguments cannot be reproduced.
  # However by hijacking the call made to the fetcher function we can make it return anything we want,
  # including the original arguments passed to it.

  # Generate an attribute set that will be used to overlay the given fetcher functions.
  # The new fetcher functions will return an attribute set represeting a call to the original fetcher function.
  overlayFetchers = names: foldr (name: overlayAttrs: let path = splitString "." name; in
    recursiveUpdate overlayAttrs (setAttrByPath path (args: {
      __fetcher = {
        inherit name args;
        fun = getAttrFromPath path pkgs;
      };
    }))) {} names;

  # In order to overlay fetchers we first need to know what attributes in the packages attribute set are actually fetchers.
  # We cannot just assume any function is a fetcher function, because the function might be needed in order to construct
  # the expression being prefetched, so it would never reach the actual fetcher call.
  topLevelFetchers = filter (name: isFetcher name pkgs.${name}) (attrNames pkgs);

  fetchersNixpkgs = fetchers: import nixpkgsPath {
    overlays = nixpkgsOverlays ++ [ (self: super: overlayFetchers fetchers) ];
  };

  fetchersOverride = pred: pkg: pkg.override (origArgs: overlayFetchers
    (filter (name: pkgs ? ${name} && pred name pkgs.${name})
    (attrNames origArgs)));

  # We always have to determine the fetcher used by a package source,
  # because even if all we have to change is the hash, we cannot be sure a hash has already been given,
  # so it might throw an error before we can override its output hash.
  prefetchedPackage =
    # If the fetcher used by the package source was explicitly given, always try and use it.
    let
      overriddenPkgSrc =
        packageSource (expr.override (origArgs:
          if fetcher != null then
            let name = last (splitString "." fetcher);
            in origArgs // optionalAttrs (origArgs ? ${name}) (overlayFetchers [ fetcher ])
          else overlayFetchers
            (filter (name: pkgs ? ${name} && isFetcher name pkgs.${name})
            (attrNames origArgs))
        ));
      fetcherPkgSrc = let fetchers = if fetcher != null then [ fetcher ] else topLevelFetchers; in
        packageSource (exprFun (fetchersNixpkgs fetchers));
      prefetch =
        # Prefer to determine the fetcher based on overridden package arguments,
        # because having to evaluate a Nixpkgs with the fetchers overlain will take more time.
        if overriddenPkgSrc ? __fetcher then prefetchDelayedFetcher overriddenPkgSrc
        else if fetcherPkgSrc ? __fetcher then prefetchDelayedFetcher fetcherPkgSrc
        else if fetcher != null then throw "the fetcher function ${fetcher} was not used by the package source"
        else throw "could not determine the fetcher used by the package source";
    in prefetch (writeLog [
      "Prefetching package ${expr.name}..."
    ]);

  prefetchDelayedFetcher = src: applyFetcher src.__fetcher;

  prefetchedFetcher = if fetcher != null
    then throw "the fetcher option should only be used in conjuction with a package derivation"
    else
      let name = maybeNull fetcher (findFirst (name: pkgs.${name} == expr) "<unnamed>" topLevelFetchers); in
      applyFetcher { inherit name; fun = expr; args = {}; } (writeLog [
        "Prefetching with fetcher ${name}..."
      ]);

  applyFetcher = { name, fun, args }: log:
    let origArgs = args; in
    let
      foundHashAlgos = intersectLists (attrNames fetcherArgs) hashAlgos;
      checkHash = foundHashAlgos == [] && hash != null || foundHashAlgos == [ hashAlgo ];
      expectedHash =
        if hash != null then if foundHashAlgos == [] then hash
          else throw "no hashes should be given as fetcher arguments when an explicit hash has been given, yet the following were given: ${toAndList foundHashAlgos}"
        else if foundHashAlgos == [] then if origArgs ? ${hashAlgo} then origArgs.${hashAlgo}
          else probablyWrongHashes.${hashAlgo}
        else if foundHashAlgos == [ hashAlgo ] then fetcherArgs.${hashAlgo}
        else if length foundHashAlgos == 1 then throw "the ${head foundHashAlgos} hash given as a fetcher argument did not match the expected hash algorithm ${hashAlgo}"
          else throw "only hashes of one algorithm are allowed, yet the following were given: ${toAndList foundHashAlgos}";
      hashArgs = singleAttr hashAlgo expectedHash;
      args = removeAttrs origArgs hashAlgos // fetcherArgs // hashArgs;
      actual = if fetchURL then {
        name = "fetchurl";
        fun = pkgs.fetchurl;
        args = let urls = sourceURLs (fun args); in if urls != []
          then { url = head urls; } // optionalAttr args "name" // hashArgs
          else throw "The fetcher ${fetcher} does not define any URLs.";
      } else {
        inherit name fun args;
      };
    in ({ name, fun, args }: prefetchSource (fun args) checkHash (log ++ writeLog (
      let toPrettyCode = x: let s = toPretty x; in replaceStrings [ "\n" ] [ "\n>   " ] s;
      in [
        "The fetcher will be run as follows:"
        "> ${name} {"
      ] ++ mapAttrsToList (name: value: ">   ${name} = ${toPrettyCode value};") args ++ [
        "> }"
        ""
      ]))) actual;

  prefetchSource = src: checkHash: origLog:
    let
      urls = sourceURLs src;
      log = origLog ++ optionals (urls != []) (writeLog ([
        "The following URLs will be fetched as part of the source:"
      ] ++ urls ++ [
        ""
      ]));
      wrongSrc = if src.outputHash != probablyWrongHashes.${hashAlgo} then src.overrideAttrs (origAttrs: {
        outputHash = probablyWrongHashes.${hashAlgo};
      }) else src;
      infoLine = concatStringsSep ":" (map toString [
        wrongSrc.drvPath
        src.drvPath
        src.out
        src.outputHash
        (stringLength wrongSrc.outputHash)
        (if checkHash then "1" else "0")
      ]);
    in concatStringsSep "\n" (log ++ [ infoLine ]);

in prefetched
