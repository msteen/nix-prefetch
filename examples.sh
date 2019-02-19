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
  printf '%s' "${title}:
"'```'"
$ nix-prefetch $(quote_args "$@")
$(nix-prefetch "$@" 2>&1)
"'```'"

"
}

{
  run-example 'A package source' hello.src
  run-example 'A package without a hash defined' test
  run-example 'A package with verbose output' hello --verbose
  run-example 'Modify the Git revision of a call to `fetchFromGitHub`' openraPackages.engines.bleed --fetch-url --rev master
  run-example 'Hash validation' hello 0000000000000000000000000000000000000000000000000000
  run-example 'A specific file fetcher' hello_rs.cargoDeps --fetcher '<nixpkgs/pkgs/build-support/rust/fetchcargo.nix>'
  run-example 'List all known fetchers in Nixpkgs' --list --deep
  run-example 'Get a specialized help message for a fetcher' fetchFromGitHub --help
  run-example 'A package for i686-linux' '(import <nixpkgs> { system = "i686-linux"; }).scilab-bin'
} > examples.md
