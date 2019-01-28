# Used by:
# listFetchers
# showFetcherHelp
# prefetch
# prefetchBuiltin

origNixpkgsPath:

let lib = with lib; import ./lib.nix // rec {
  # We cannot simply overwrite the default overlays, because they might be used,
  # so we need to determine the default overlays and add to them our overlay.
  # Unfortunately there is no way to get the overlays after configuring a Nixpkgs with them,
  # so instead we use scoped imports to overwrite the default import definition in such a way
  # that instead of returning the Nix packages set, we have it return its own arguments.
  nixpkgsOverlays =
    let
      customImport = scopedImport {
        import = path: if path == nixpkgsPath + /pkgs/top-level then (args: args) else customImport path;
      };
    in (customImport nixpkgsPath { }).overlays;

  # Generate an attribute set that will be used to overlay the given fetcher functions.
  # The new fetcher functions will return an attribute set represeting a call to the original fetcher function.
  overlayFetchers = names: customFetcher: foldr (name: overlayAttrs: let path = splitString "." name; in
    recursiveUpdate overlayAttrs (setAttrByPath path (customFetcher { inherit name path; }))
  ) {} names;

  builtinPkgs = {
    builtins = builtins // { recurseForDerivations = true; };
  };

  listFetchers = deep: pkgs:
    let
      collectFetchers = parents: pkgs:
        concatLists (mapAttrsToList (name: x:
          let names = parents ++ [ name ];
          in if isFetcher name x then [ (concatStringsSep "." names) ]
          else if deep && isRecursable x then collectFetchers names x
          else []
        ) pkgs);

    in collectFetchers [] pkgs;

  # The expression is defined as a function to allow us to bring the `pkgs` attribute of Nixpkgs into scope,
  # upon which the actual expression might be dependent.
  toExprFun = { type, expr }:
    if type == "file" then const (
      let
        imported = import expr;
        # When the file contains a function that can be auto-called, do so.
        content = if isFunction imported && all id (attrValues (functionArgs imported)) then imported { } else imported;
      in try (callPackage content) content)
    else if type == "str" then const expr
    else expr;

  # The Nixpkgs path is a Nix expression that produces such a path,
  # so since it requires evaluation, we can only validate it within Nix.
  nixpkgsPath = let checkPath = origNixpkgsPath + /pkgs/top-level; in
    if pathExists checkPath then origNixpkgsPath
    else throw "Invalid Nixpkgs path, could not find path '${toString checkPath}'.";

  pkgs =
    let origPkgs = import nixpkgsPath { } // builtinPkgs;
    in if isNixpkgs origPkgs then origPkgs
    else throw "Invalid Nixpkgs path, it did not evaluate to an attribute set with the expected attributes.";

  # In order to overlay fetchers we first need to know what attributes in the packages attribute set are actually fetchers.
  # We cannot just assume any function is a fetcher function, because the function might be needed in order to construct
  # the expression being prefetched, so it would never reach the actual fetcher call.
  topLevelFetchers = filter (name: isFetcher name pkgs.${name}) (attrNames pkgs);
};

in lib
