{ prelude, fetcher, usage, ... }:

with prelude;

let
  toOptionList = names: concatStringsSep "\n" (map (s: "  " + s) (if names != []
    then map (name: "--${name}") names
    else [ "<none>" ]));

  optionalArgs =
    let args = functionArgs fetcher;
    in partition (name: args.${name}) (attrNames args);

in ''
  Prefetch the ${fetcher.name} function call

  Usage:
    nix-prefetch ${fetcher.name}
  ${usage}

  Fetcher options (required):
  ${toOptionList optionalArgs.wrong}

  Fetcher options (optional):
  ${toOptionList optionalArgs.right}
''
