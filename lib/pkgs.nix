{ prelude, nixpkgsPath }@orig:

with prelude;

let
  nixpkgsPath = toPath orig.nixpkgsPath;

  pkgsTopLevelPath = nixpkgsPath + /pkgs/top-level;

# The Nixpkgs path is a Nix expression that produces such a path,
# since it requires evaluation, we can only validate it within Nix.
in if pathExists pkgsTopLevelPath then
  let pkgs = import nixpkgsPath { };
  in if pkgs ? pkgs && pkgs ? path && pkgs ? lib && pkgs ? config then pkgs
  else throw "Nixpkgs path did not evaluate to a Nixpkgs attribute set."
else throw "Could not find Nixpkgs path: ${toString pkgsTopLevelPath}."
