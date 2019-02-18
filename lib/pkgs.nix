origNixpkgsPath:

let prelude = import ./prelude.nix; in with prelude;

let
  nixpkgsPath = if builtins.typeOf origNixpkgsPath != "path"
    then /. + substring 1 (-1) (builtins.unsafeDiscardStringContext (toString origNixpkgsPath))
    else origNixpkgsPath;

  pkgsTopLevelPath = nixpkgsPath + /pkgs/top-level;

  # We cannot simply overwrite the default overlays, because they might be used,
  # so we need to determine the default overlays and add to them our overlay.
  # Unfortunately there is no way to get the overlays after configuring a Nixpkgs with them,
  # so instead we use scoped imports to overwrite the default import definition in such a way
  # that instead of returning the Nix packages set, we have it return its own arguments.
  nixpkgsOverlays =
    let
      customImport = scopedImport {
        import = path: if path == pkgsTopLevelPath then (args: args) else customImport path;
      };
    in (customImport nixpkgsPath { }).overlays;

# The Nixpkgs path is a Nix expression that produces such a path,
# since it requires evaluation, we can only validate it within Nix.
in if builtins.pathExists pkgsTopLevelPath then
  let pkgs = import nixpkgsPath { };
  in if pkgs ? pkgs && pkgs ? path && pkgs ? lib && pkgs ? config then { inherit prelude pkgs; }
  else throw "Nixpkgs path did not evaluate to a Nixpkgs attribute set."
else throw "Could not find Nixpkgs path: ${toString pkgsTopLevelPath}."
