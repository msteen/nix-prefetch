origNixpkgsPath:

let prelude = import ./prelude.nix; in with prelude;

let
  nixpkgsPath = toPath origNixpkgsPath;

  pkgsTopLevelPath = nixpkgsPath + /pkgs/top-level;

# The Nixpkgs path is a Nix expression that produces such a path,
# since it requires evaluation, we can only validate it within Nix.
in if builtins.pathExists pkgsTopLevelPath then
  let pkgs = import nixpkgsPath { };
  in if pkgs ? pkgs && pkgs ? path && pkgs ? lib && pkgs ? config then { inherit prelude pkgs; }
  else throw "Nixpkgs path did not evaluate to a Nixpkgs attribute set."
else throw "Could not find Nixpkgs path: ${toString pkgsTopLevelPath}."
