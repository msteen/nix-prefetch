{ prelude, pkgs, deep }:

with prelude;

let
  recur = parents: pkgs:
    concatLists (mapAttrsToList (name: x:
      let names = parents ++ [ name ];
      in if isFetcher name then [ (concatStringsSep "." names) ]
      else if deep && isRecursable x then recur names x
      else []
    ) pkgs);

in recur [] pkgs
