{ fetcher ? throw "Unknown fetcher.", forceHTTPS ? false }@orig:

let prelude = with prelude; import ./lib.nix // {
  fetcher = if orig.fetcher == null || elem orig.fetcher.type [ "file" "attr" ]
    then orig.fetcher
    else throw "Unsupported fetcher type '${type}'.";

  # The value is defined as a function to allow us to bring the `pkgs` attribute of Nixpkgs into scope,
  # upon which the actual value might be dependent.
  toExprFun = { type, value, ... }@orig: pkgs:
    if type == "str" then value
    else if elem type [ "file" "attr" "expr" ] then
      let value = if type == "file" then import orig.value else orig.value pkgs;
      in tryCallPackage pkgs (if isFunction value && all id (attrValues (functionArgs value)) then value { } else value)
    else throw "Unsupported expression type '${type}'.";

  # To support builtin fetchers like any other, they too should be in the package set.
  # To fix `functionArgs` for the builtin fetcher functions, we need to wrap them via `setFunctionArgs`.
  builtinsOverlay =
    let
      fixedFunctionArgsBuiltins = mapAttrs (name: x:
        if builtinFunctionArgs ? ${name}
        then setFunctionArgs x builtinFunctionArgs.${name}
        else x
      ) builtins // { recurseForDerivations = true; };
    in {
      builtins = fixedFunctionArgsBuiltins;

      # The builtin is also available outside of `builtins`.
      inherit (fixedFunctionArgsBuiltins) fetchTarball;
    };

  # Using `scopedImport` is rather slow. On my machine prefetching hello went from roughly 600ms to roughly 1200ms,
  # which is why its only used when all other attempts of determining the fetcher's source have failed.
  scopedNixpkgsImport = path: config:
    let
      pkgs = recursiveUpdate (customImport path config) { builtins.import = customImport; };
      customImport = scopedImport (builtinsOverlay // {
        import = path: if isFetcherPath path || fetcher.type or null == "file" && path == fetcher.value
          then importFetcher path
          else customImport path;
      });
    in pkgs;

  # Due to files like `pkgs/development/compilers/elm/fetchElmDeps.nix`,
  # it is ambiguous whether a file defined a fetcher function or not.
  # Two type of fetcher function files are supported, those that define fetchers straight away,
  # and those that require additional dependencies. Unifying the two types by checking if `callPackage`
  # can be called to supply the dependencies will not work, because not all dependencies are set via `callPackage`.
  # So the current approach is to actually see if the functions are fetcher functions (i.e. produce derivations),
  # and otherwise just make it behave as normal.
  importFetcher = path:
    let
      type = "file";
      name = toString path;
      x = import path;
      fx = args:
        let
          # We cannot supply the required fetcher arguments for imported fetchers like we do for fetcher functions,
          # because we don't know beforehand whether it is a fetcher function or not.
          y = x args;
          fy = args:
            let z = y args;
            in if isDerivation z then markFetcherDrv { inherit type name args; fetcher = y; drv = z; }
            else z;
        in if isFunction y then setFunctionArgs fy (functionArgs y)
        else if isDerivation y then markFetcherDrv { inherit type name args; fetcher = x; drv = y; }
        else y;
    in if isFunction x
    then setFunctionArgs fx (functionArgs x)
    else x;

  # Generate an attribute set that will be used to overlay the given fetcher functions.
  # The new fetcher functions will return an attribute set represeting a call to the original fetcher function.
  genFetcherOverlay = pkgs: names:
    let
      paths = map (name: splitString "." name) names;
      genFetcher = name: path: setAttrByPath path (markFetcher {
        type = "attr";
        inherit name;
        fetcher = getAttrFromPath path pkgs;
      });
      orig = genAttrs (concatMap (path: take 1 (init path)) paths) (name: pkgs.${name});
    in foldl' recursiveUpdate orig (zipListsWith genFetcher names paths);

  primitiveFetchers = listFetchers builtinsOverlay true ++ [ "fetchurlBoot" ];

  markFetcher = { type, name, fetcher }:
    let
      customFetcher = args: markFetcherDrv { inherit type name fetcher args; drv = fetcher (requiredFetcherArgs // args); };

      # The required fetcher arguments are assumed to be of type string,
      # because requiring a complex value, e.g. a derivation attrset, is very unlikely,
      # and all other simple types have likely defaults: null, false/true, 0/1, [], {}.
      requiredFetcherArgs = mapAttrs (_: _: "") (filterAttrs (_: isOptional: !isOptional) (functionArgs fetcher));

    in setFunctionArgs customFetcher (functionArgs fetcher) // {
      __fetcher = (if !(elem name primitiveFetchers) then setFunctionArgs fetcher (functionArgs (customFetcher requiredFetcherArgs).__fetcher) else fetcher)
        // { inherit type name; args = {}; };
    };

  markFetcherDrv = { type, name, fetcher, args, drv ? fetcher args }: let drvOverriden = (drv.overrideAttrs or (const drv)) (origAttrs:
    let
      origPassthru = origAttrs.passthru or {};
      oldArgs =
        if origPassthru ? __fetcher then
          if !(elem origPassthru.__fetcher.name primitiveFetchers) then functionArgs origPassthru.__fetcher
          else throw "Fetcher ${name} is build on top of the primitive fetcher ${origPassthru.__fetcher.name}, which is not supported."
        else {};
      newArgs = oldArgs // functionArgs fetcher // mapAttrs (_: _: true) (builtins.intersectAttrs args oldArgs);
    in {
      passthru = origPassthru // {
        __fetcher = setFunctionArgs fetcher newArgs // { inherit type name args; drv = drvOverriden; };
      };
    }); in drvOverriden;

  # The error "called without required argument" cannot be handled by `tryEval`,
  # so we need to make sure that `callPackage` will succeed before calling it.
  attemptCallPackage = pkgs: x:
    let
      needed = functionArgs x;
      found = builtins.intersectAttrs needed pkgs;
    in if isFunction x && attrNames needed == attrNames found
    then { success = true; value = makeOverridable x found; }
    else { success = false; value = null; };

  tryCallPackage = pkgs: x: let call = attemptCallPackage pkgs x; in if call.success then call.value else x;

  listFetchers = pkgs: deep:
    let
      recur = parents: pkgs:
        concatLists (mapAttrsToList (name: x:
          let names = parents ++ [ name ];
          in if isFetcher name && isFunction x then [ (concatStringsSep "." names) ]
          else if deep && isRecursable x then recur names x
          else []
        ) pkgs);
    in recur [] pkgs;

  toHTTPS = url: if hasPrefix "http://" url then "https://${removePrefix "http://" url}" else url;

  builtinFunctionArgs =
    mapAttrs (_: value: { name = true; } // value) (mapAttrs (_: value: {
      hash = true;
      md5 = true;
      sha1 = true;
      sha256 = true;
      sha512 = true;
    } // value) {
      fetchurl = {
        url = false;
      };
      fetchTarball = {
        url = false;
      };
    } // {
      fetchGit = {
        url = false;
        rev = true;
        ref = true;
      };
      fetchMercurial = {
        url = false;
        rev = true;
      };
    });

  hashEncodings = {
    base16 = {
      regex = "[a-f0-9]+";
      lengths = {
        md5    = 32;
        sha1   = 40;
        sha256 = 64;
        sha512 = 128;
      };
    };
    base32 = {
      regex = "[a-z0-9]+";
      lengths = {
        md5    = 26;
        sha1   = 32;
        sha256 = 52;
        sha512 = 103;
      };
    };
    base64 = {
      regex = "[A-Za-z0-9+/=]+";
      lengths = {
        md5    = 24;
        sha1   = 28;
        sha256 = 44;
        sha512 = 88;
      };
    };
  };

  hashAlgos = attrNames hashEncodings.base16.lengths;

  # The most obivous probably-wrong output hashes are zero valued output hashes, so they will be used.
  # The hashes are using base 32 encoding, because the actual output hash being reported in the hash mismatch error message
  # will also be using this encoding. For the purpose of having a probably-wrong output hash,
  # any other valid hash encoding would have been fine though.
  probablyWrongHashes = mapAttrs (_: length: repeatString length "0") hashEncodings.base32.lengths;
}; in prelude
