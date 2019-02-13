let lib = builtins // import <nixpkgs/lib>; in with lib; lib // rec {
  applyIf = b: f: x: if b then f x else x;
  quotRem = x: y: rec { quot = builtins.div x y; rem = x - y * quot; };
  repeatString = n: s:
    let
      egyptianMul = out: n: dbl:
        if n > 1
        then let inherit (quotRem n 2) quot rem;
          in egyptianMul (if rem > 0 then out + dbl else out) quot (dbl + dbl)
        else out + dbl;
    in if n < 1 then "" else egyptianMul "" n s;
  foldrAttrs = op: nul: attrs: foldr (name: res: op name attrs.${name} res) nul (attrNames attrs);
  isPath = x: typeOf x == "path" || isString x && hasPrefix "/" x;
  isRecursable = x: try (x.recurseForDerivations or false) false;
  # The following would have been the most accurate, but it would require evaluation:
  # builtins.intersectAttrs (functionArgs x) (genAttrs (const null) hashAlgos) != {}
  isFetcher = name: x: name == "requireFile" || hasPrefix "fetch" name && isFunction x;
  isFetcherPath = path: hasPrefix "fetch" (baseNameOf path);
  isSource = x: x ? outputHash && x ? outputHashMode && x ? outputHashAlgo;
  isPackage = x: isDerivation x && (x ? src || x ? srcs) && !(isSource x);
  isNixpkgs = x: x ? pkgs && x ? path && x ? lib && x ? config;
  try = x: default: let res = tryEval x; in if res.success then res.value else default;
  functionArgs = f:
    if f ? __functor && isFunction (f.__functor f) then f.__functionArgs or (builtins.functionArgs (f.__functor f))
    else builtins.functionArgs f;
  singleAttr = name: value: listToAttrs (singleton (nameValuePair name value));
  setAttr = name: value: attrs: attrs // singleAttr name value;
  inheritAttr = attrs: name: singleAttr name attrs.${name};
  optionalAttr = attrs: name: if attrs ? ${name} then inheritAttr attrs name else {};
  maybeNull = x: default: if x != null then x else default;
  toExpr = x: if isPath x then import x else x;
  toPretty = v: generators.toPretty { allowPrettyValues = true; } (let pr = f: { __pretty = f; val = v; }; in
    if isString v && match ".*\n.*" v != null then pr (s:
      "''" + concatMapStrings (s: "\n  " + s) (splitString "\n" (removeSuffix "\n" s)) + "${optionalString (hasSuffix "\n" s) "\n"}''"
    ) else v);
  toEnglishList = sep: list: let lastIndex = length list - 1; in concatStringsSep ", " (sublist 0 lastIndex list ++ [ "${sep} ${elemAt list lastIndex}" ]);
  toAndList = toEnglishList "and";
  lines = ss: concatMapStrings (s: s + "\n") ss;
  lines' = ss: concatStringsSep "\n" ss;
  toShell = attrs: lines (mapAttrsToList (name: value: "${name}=${value}") attrs);

  # Generate an attribute set that will be used to overlay the given fetcher functions.
  # The new fetcher functions will return an attribute set represeting a call to the original fetcher function.
  genFetcherOverlay = pkgs: names: genFetcher:
    foldr (name: overlayAttrs:
      let
        type = "attr";
        path = splitString "." name;
        value = getAttrFromPath path pkgs;
      in recursiveUpdate overlayAttrs (setAttrByPath path (args: genFetcher { inherit type name value args; }))
    ) {} names;

  customImportNixpkgs = path: config: pred: action:
    let customImport = scopedImport { import = path: if pred path then action path else customImport path; };
    in customImport path config;

  fetcherDrvNixpkgs = pkgs: fetchers: markFetcherDrv:
    let
      genFetcher = orig: markFetcherDrv (orig // { drv = with orig; value args; });

      config = {
        overlays = pkgs.overlays ++ [ (self: super: genFetcherOverlay super fetchers genFetcher) ];
      };

      importFetcher = path:
        let
          type = "file";
          name = toString path;
          value = import path;
          customFun = args:
            let fetcherOrDrv = value args;
            in if isFunction fetcherOrDrv
            then setFunctionArgs (args: genFetcher { inherit type name args; value = fetcherOrDrv; }) (functionArgs fetcherOrDrv)
            else markFetcherDrv { inherit type name value args; drv = fetcherOrDrv; };
        in setFunctionArgs customFun (functionArgs value);

    in customImportNixpkgs pkgs.path config isFetcherPath importFetcher;

  # The value is defined as a function to allow us to bring the `pkgs` attribute of Nixpkgs into scope,
  # upon which the actual value might be dependent.
  toExprFun = { type, value, ... }@orig: pkgs:
    if type == "str" then value
    else if elem type [ "file" "attr" "expr" ] then
      # The error "called without required argument" cannot be handled by `tryEval`,
      # so we cannot automatically try `callPackage`.
      let value = if type == "file" then import orig.value else orig.value pkgs;
      in if isFunction value && all id (attrValues (functionArgs value)) then value { } else value
    else throw "Unsupported expression type '${type}'.";

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
}
