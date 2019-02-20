#!/usr/bin/env bash

nix-prefetch() {
  case $PWD in
    */nix-prefetch/src) ./main.sh "$@";;
    */nix-prefetch/lib) ../src/main.sh "$@";;
    */nix-prefetch) ./src/main.sh "$@";;
    *) command nix-prefetch "$@"
  esac
}
