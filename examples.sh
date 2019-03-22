#!/usr/bin/env bash
# shellcheck disable=SC1003 disable=SC2016

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
  printf '%s\n' " *nix-prefetch* $(quote_asciidoc "$@")" >> /dev/fd/3
  printf '\n%s\n' "${title}:
"'```'"
$ nix-prefetch $(quote_args "$@")
$(nix-prefetch "$@" 2>&1)
"'```' >> /dev/fd/4
}

{
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
  run-example 'Passing a list rather than a string argument' \
    nix-prefetch fetchurl --urls --expr '[ mirror://gnu/hello/hello-2.10.tar.gz ]'
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

  printf -v examples '\n[subs="verbatim,quotes"]\n%s\n' "$(< /dev/fd/3)"
  examples=${examples//\\/\\\\}
  printf '%s\n' "$(awk -v "examples=$examples" '
    $0 == "== Examples" { skip=1; print; print examples; next }
    skip && $1 == "==" { skip=0 }
    !skip { print }
  ' doc/nix-prefetch.1.asciidoc)" > doc/nix-prefetch.1.asciidoc

  examples=$(< /dev/fd/4)
  examples=${examples//\\/\\\\}
  printf '%s\n' "$(awk -v "examples=$examples" '
    $0 == "Examples" { skip=1; print; next }
    skip && $0 == "---" { print; print examples; exit }
    skip { skip=0 }
    { print }
  ' README.md)" > README.md
} 3<<EOF 4<<EOF
EOF
EOF
