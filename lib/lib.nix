let lib = builtins // import <nixpkgs/lib>; in with lib; lib // rec {
  applyIf = b: f: x: if b then f x else x;
  quotRem = x: y: rec { quot = div x y; rem = x - y * quot; };
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
  isFetcher = name: name == "requireFile" || hasPrefix "fetch" name;
  isFetcherPath = path: let name = baseNameOf path; in hasPrefix "fetch" name && hasSuffix ".nix" name && name != "fetcher.nix";
  isSource = x: x ? outputHash && x ? outputHashMode && x ? outputHashAlgo;
  isPackage = x: isDerivation x && (x ? src || x ? srcs) && !(isSource x);
  try = x: default: let eval = tryEval x; in if eval.success then eval.value else default;
  functionArgs = f:
    if f ? __functor && isFunction (f.__functor f) then f.__functionArgs or (builtins.functionArgs (f.__functor f))
    else builtins.functionArgs f;
  singleAttr = name: value: listToAttrs (singleton (nameValuePair name value));
  setAttr = name: value: attrs: attrs // singleAttr name value;
  inheritAttr = attrs: name: singleAttr name attrs.${name};
  optionalAttr = attrs: name: if attrs ? ${name} then inheritAttr attrs name else {};
  maybeNull = x: default: if x != null then x else default;
  toPath = x: if builtins.typeOf x != "path"
    then /. + substring 1 (-1) (builtins.unsafeDiscardStringContext (toString x))
    else x;
  toExpr = x: if isPath x then import x else x;
  toPretty = v: generators.toPretty { allowPrettyValues = true; } (let pr = f: { __pretty = f; val = v; }; in
    if isString v && match ".*\n.*" v != null then pr (s:
      "''" + concatMapStrings (s: "\n  " + s) (splitString "\n" (removeSuffix "\n" s)) + "${optionalString (hasSuffix "\n" s) "\n"}''"
    ) else v);
  toEnglishList = sep: list: let lastIndex = length list - 1; in concatStringsSep ", " (sublist 0 lastIndex list ++ [ "${sep} ${elemAt list lastIndex}" ]);
  toAndList = toEnglishList "and";
  lines = ss: concatMapStrings (s: s + "\n") ss;
  lines' = ss: concatStringsSep "\n" ss;
}
