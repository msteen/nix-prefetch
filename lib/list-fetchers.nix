{ lib, pkgs, deep ? false }:

with lib;

let
  listFetchers = parents: pkgs:
    concatLists (mapAttrsToList (name: x:
      let names = parents ++ [ name ];
      in if isFetcher name x then [ (concatStringsSep "." names) ]
      else if deep && isRecursable x then listFetchers names x
      else []
    ) pkgs);

in listFetchers [] pkgs
