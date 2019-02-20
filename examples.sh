#!/usr/bin/env bash

quote() {
  grep -q '^[a-zA-Z0-9_\.-]\+$' <<< "$*" && printf '%s' "$*" || printf '%s' "'${*//'/\\'}'"
}

quote_args() {
  for arg in "$@"; do
    printf '%s ' "$(quote "$arg")"
  done
}

run-example() {
  title=$1; shift
  shift # nix-prefetch
  printf '%s' "${title}:
"'```'"
$ nix-prefetch $(quote_args "$@")
$(nix-prefetch "$@" 2>&1)
"'```'"

"
}

{
  run-example 'A package source' \
    nix-prefetch hello.src
  run-example 'A package without a hash defined' \
    nix-prefetch test
  run-example 'A package checked to already be in the Nix store thats not installed' \
    nix-prefetch hello --check-store --verbose
  run-example 'A package checked to already be in the Nix store thats installed (i.e. certain the hash is valid, no need to redownload)' \
    nix-prefetch git --check-store --verbose
  run-example 'Modify the Git revision of a call to `fetchFromGitHub`'\
    nix-prefetch openraPackages.engines.bleed --fetch-url --rev master
  run-example 'Hash validation' \
    nix-prefetch hello 0000000000000000000000000000000000000000000000000000
  run-example 'A specific file fetcher' \
    nix-prefetch hello_rs.cargoDeps --fetcher '<nixpkgs/pkgs/build-support/rust/fetchcargo.nix>'
  run-example 'List all known fetchers in Nixpkgs' \
    nix-prefetch --list --deep
  run-example 'Get a specialized help message for a fetcher' \
    nix-prefetch fetchFromGitHub --help
  run-example 'A package for i686-linux' \
    nix-prefetch '(import <nixpkgs> { system = "i686-linux"; }).scilab-bin'
} > examples.md
