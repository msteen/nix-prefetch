{ prelude, pkgs, expr, index, fetcher }@orig:

with prelude;

let
  exprFun = toExprFun orig.expr;
  expr = exprFun pkgs;
  pkg = if isPackage expr then expr else null;

  toSource = x:
    if isSource x then x
    else if x ? srcs then
      if index != null then elemAt x.srcs index
      # If the index is undefined when it is actually needed, we choose to require to be explicit about it,
      # so instead of defaulting to 0, we throw an error.
      else throw "No index has been given, which is necessary to choose one of the multiple sources."
    else x.src or (throw "The expression could not be coerced to a source.");

  metaFromExpr = with orig.expr;
    if type == "attr" then { type = "attr"; inherit name; }
    else if type == "file" then { type = "file"; name = toString value; }
    else if type == "expr" then
      if isPath expr then { type = "file"; name = toString expr; }
      else { type = "attr"; name = "<unnamed>"; }
    else throw "Unsupported expression type '${type}'.";

  fetcherFromFn =
    if fetcher == null then expr.__fetcher or (markFetcher (metaFromExpr // { fetcher = expr; })).__fetcher
    else throw "The fetcher option should only be used in conjuction with a package derivation.";

  # We always have to determine the fetcher used by a package source,
  # because even if all we have to change is the hash, we cannot be sure a hash has already been given,
  # so it might throw an error before we can override its output hash.
  fetcherFromSrc =
    let
      src = toSource expr;
      srcFromOverride = if pkg == null then null else toSource (pkg.override (origArgs:
        genFetcherOverlay pkgs (filter (name: pkgs ? ${name} && isFetcher name pkgs.${name}) (attrNames origArgs))));
      srcFromScoped = toSource (exprFun (fetchersImport pkgs));
    # Most of the time the fetcher will be passed as a package argument,
    # and it might not be present under that name in the global Nixpkgs namespace,
    # so we try looking up fetchers in the passed arguments first.
    in srcFromOverride.__fetcher or src.__fetcher or srcFromScoped.__fetcher or (throw "Could not determine the fetcher used by the source.");

in if isFunction expr then { inherit pkg; fetcher = fetcherFromFn; }
else if isPackage expr || isSource expr then { inherit pkg; fetcher = fetcherFromSrc; }
else throw "The expression does not resolve to either fetcher function, package derivation, or source derivation."
