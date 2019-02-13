{ lib ? import ./lib.nix, nixpkgsPath }@orig:

with lib;

let
  # The Nixpkgs path is a Nix expression that produces such a path,
  # since it requires evaluation, we can only validate it within Nix.
  nixpkgsPath =
    let
      nixpkgsPath = /. + substring 1 (-1) (builtins.unsafeDiscardStringContext (toString orig.nixpkgsPath));
      checkPath = nixpkgsPath + /pkgs/top-level;
    in if pathExists checkPath then nixpkgsPath
    else throw "Could not find Nixpkgs path '${toString checkPath}'.";

  builtinFetcherArgs =
    mapAttrs (_: value: {
      hash = true;
      md5 = true;
      sha1 = true;
      sha256 = true;
      sha512 = true;
      name = true;
    } // value) {
      fetchurl = {
        url = false;
      };

      fetchTarball = {
        url = false;
      };

      fetchGit = {
        url = false;
        rev = false;
        ref = false;
      };
    };

  pkgs = import nixpkgsPath { } // {
    # To support builtin fetchers like any other, they too should be in the package set.
    # To fix `functionArgs` for the builtin fetcher functions, we need to wrap them via `setFunctionArgs`.
    builtins = mapAttrs (name: value: if builtinFetcherArgs ? ${name} then setFunctionArgs value builtinFetcherArgs.${name} else value) builtins
      // { recurseForDerivations = true; };

    # The builtin is also available outside of `builtins`.
    fetchTarball = pkgs.builtins.fetchTarball;

    # We cannot simply overwrite the default overlays, because they might be used.
    # Unfortunately there is no way to get the overlays after configuring a Nixpkgs with them,
    # so instead we use scoped imports to overwrite the default import definition in such a way
    # that instead of returning the package set, it returns its own arguments.
    overlays = (customImportNixpkgs pkgs.path { } (path: path == pkgs.path + /pkgs/top-level) (_: args: args)).overlays;

    # In order to overlay fetchers we first need to know what attributes in the packages attribute set are actually fetchers.
    # We cannot just assume any function is a fetcher function, because the function might be needed in order to construct
    # the expression being prefetched, so it would never reach the actual fetcher call.
    topLevelFetchers = filter (name: isFetcher name pkgs.${name}) (attrNames pkgs);
  };

in if isNixpkgs pkgs then { inherit lib pkgs; }
else throw "Nixpkgs path did not evaluate to an attribute set with attributes expected from Nixpkgs."
