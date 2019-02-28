#!/usr/bin/env bash

quote_args() {
  for arg in "$@"; do
    printf '%s ' "$( [[ $arg =~ ^[a-zA-Z0-9_\.-]+$ ]] <<< "$arg" && printf '%s' "$arg" || printf '%s' "'${arg//'/\\'}'" )"
  done
}

quote_asciidoc() {
  for arg in "$@"; do
    printf '%s ' "$( [[ $arg =~ ^[a-zA-Z0-9_\.-]+$ ]] && {
      [[ $arg == -* ]] && printf '*%s*' "$arg" || printf '%s' "$arg"
    } || printf '%s' "\\'${arg//'/\\'}'" )"
  done
}

run-example() {
  title=$1; shift
  shift # nix-prefetch
  printf '%s\n\n' "${title}:
"'```'"
$ nix-prefetch $(quote_args "$@")
$(nix-prefetch "$@" 2>&1)
"'```' >> examples.md
  printf '%s\n' " *nix-prefetch* $(quote_asciidoc "$@")" >> examples.asciidoc
}

> examples.md
> examples.asciidoc

run-example 'A package source' \
  nix-prefetch hello.src
run-example 'A package without a hash defined' \
  nix-prefetch '{ stdenv, fetchurl }: stdenv.mkDerivation rec {
                name = "test";
                src = fetchurl { url = http://ftpmirror.gnu.org/hello/hello-2.10.tar.gz; };
              }'
run-example 'A package checked to already be in the Nix store thats not installed' \
  nix-prefetch hello --check-store --verbose
run-example 'A package checked to already be in the Nix store thats installed (i.e. certain the hash is valid, no need to redownload)' \
  nix-prefetch git --check-store --verbose
run-example 'Modify the Git revision of a call to `fetchFromGitHub`'\
  nix-prefetch openraPackages.engines.bleed --fetchurl --rev master
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

truncate -s -1 examples.md
