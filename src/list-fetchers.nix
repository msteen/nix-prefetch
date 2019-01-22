{ lib, file, deep }:

with lib;

let
  listFetchers = parents: pkgs:
    concatLists (mapAttrsToList (name: x:
      let names = parents ++ [ name ];
      in if isFetcher name x then [ (concatStringsSep "." names) ]
      else if deep && isRecursable x then listFetchers names x
      else []
    ) pkgs);

  pkgs = if isFunction file then file { } else file;

  fetchers = listFetchers [] (pkgs // {
    builtins = builtins // { recurseForDerivations = true; };
  });

in lines fetchers
