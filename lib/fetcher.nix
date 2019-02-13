{ lib, pkgs, expr, index, fetcher }@orig:

with lib;

let
  exprFun = toExprFun orig.expr;
  expr = exprFun pkgs;

  builtinFetchers = import ./list-fetchers.nix {
    inherit lib;
    pkgs = { builtins = builtins // { recurseForDerivations = true; }; };
    deep = true;
  };

  inherit (pkgs) topLevelFetchers;

  toSource = x:
    if isSource x then x
    else if x ? srcs then
      if orig.index != null then elemAt x.srcs orig.index
      # If the index is undefined when it is actually needed, we choose to require to be explicit about it,
      # so instead of defaulting to 0, we throw an error.
      else throw "No index has been given, which is necessary to choose one of the multiple sources."
    else x.src or (throw "The expression could not be coerced to a source.");

  # FIXME: Expression based fetchers will fail due to not being able to determine the name. Do something like `srcFromOverlay`.
  fromFetcher = fetcher:
    if orig.fetcher != null then throw "The fetcher option should only be used in conjuction with a package derivation."
    else let
      nameExpr = exprFun (import pkgs.path {
        overlays = pkgs.overlays ++ [ (self: super:
          genFetcherOverlay super (builtinFetchers ++ topLevelFetchers) ({ name, ... }: name)
        ) ];
      });

      # FIXME: What if the expression produced a file, should that file not be its name?
      inherit (let inherit (orig.expr) type value; in
        if type == "attr" then { type = "attr"; name = orig.expr.name; }
        else if type == "file" then { type = "file"; name = toString value; }
        else if type == "expr" then
          if isString nameExpr then { type = "attr"; name = nameExpr; }
          else throw "The name of the fetcher is required, yet the name of the fetcher expression could not be determined."
        else throw "Unsupported expression type '${type}'.") type name;

    in { pkg = null; fetcher = { inherit type name; value = fetcher; args = {}; }; };

  # We always have to determine the fetcher used by a package source,
  # because even if all we have to change is the hash, we cannot be sure a hash has already been given,
  # so it might throw an error before we can override its output hash.
  fromSource = pkg:
    let
      markFetcherDrv = { value, args, drv ? value args,... }@orig: drv // {
        __fetcher = removeAttrs orig [ "drv" ];
      };

      srcFromOverlay = fetchers: toSource (exprFun (fetcherDrvNixpkgs pkgs fetchers markFetcherDrv));

      __fetcherFrom = pkgOverride: srcFromOverlay: error:
        let srcFromOverride = toSource (pkg.override pkgOverride);
        in if pkg != null && srcFromOverride ? __fetcher then srcFromOverride.__fetcher
        else if srcFromOverlay ? __fetcher then srcFromOverlay.__fetcher
        else throw error;

      __fetcher =
        # If the fetcher to be used was explicitly given, always try and use it.
        if fetcher != null then let inherit (fetcher) type value; in
          if type == "file" then
            let srcFromFetcherPath = toSource (exprFun (customImportNixpkgs pkgs.path { } (path: path == value) importFetcher));
            in if srcFromFetcherPath ? __fetcher then srcFromFetcherPath.__fetcher
            else throw "The fetcher file ${toString value} was not used by the source."
          else if type == "str" then __fetcherFrom
            (origArgs: optionalAttrs (origArgs ? ${last (splitString "." value)}) (genFetcherOverlay pkgs [ value ] markFetcherDrv))
            (srcFromOverlay [ value ])
            "The fetcher ${toString value} was not used by the source."
          else throw "Unsupported fetcher type '${type}'."
        else __fetcherFrom
          (origArgs: genFetcherOverlay pkgs (filter (name: pkgs ? ${name} && isFetcher name pkgs.${name}) (attrNames origArgs)) markFetcherDrv)
          (srcFromOverlay topLevelFetchers)
          "Could not determine the fetcher used by the source.";

    in { inherit pkg; fetcher = __fetcher; };

in if isFunction expr then fromFetcher expr
else if isPackage expr then fromSource expr
else if isSource expr then fromSource null
else throw "The expression does not resolve to either fetcher function, package derivation, or source derivation."
