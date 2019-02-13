{ lib, pkgs, pkg, fetcher }:

with lib;

let
  toOptionList = names: if names != []
    then concatStringsSep "\n" (map (name: "  --${name}") names)
    else "  <none>";

  optionalList = let fetcherArgs = import ./fetcher-function-args.nix { inherit lib pkgs fetcher; }; in
    mapAttrs (_: toOptionList) (partition (name: fetcherArgs.${name}) (attrNames fetcherArgs));

in ''
  The fetcher ${fetcher.name} produces a fixed-output derivation to use as a source.

  All options can be repeated with the last value taken,
  and can placed both before and after the parameters.

  To keep the usage section simple, the possible fetcher options have not been listed.
  They can be found in their own sections instead.

  Usage:
    nix-prefetch ${fetcher.name}
                 [(-f | --file) <file>] [--fetch-url]
                 [(-t | --type | --hash-algo) <hash-algo>] [(-h | --hash) <hash>]
                 [--input <input-type>] [--output <output-type>] [--print-path]
                 [--no-hash] [--force] [-s | --silent] [-q | --quiet] [-v | --verbose] [-vv | --debug] ...
                 [<hash>]
                 [--] [--<name> ((-f | --file) <file> | (-A | --attr) <attr> | (-E | --expr) <expr> | <str>) | --autocomplete <word> | --help] ...

  Fetcher options (required):
  ${optionalList.wrong}

  Fetcher options (optional):
  ${optionalList.right}
''
