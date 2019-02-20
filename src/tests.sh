#!/usr/bin/env bash

bin='@bin@'

script_args=( "$@" )

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

quote() {
  grep -q '^[a-zA-Z0-9_\.-]\+$' <<< "$*" && printf '%s' "$*" || printf '%s' "'${*//'/\\'}'"
}

quote_args() {
  for arg in "$@"; do
    printf '%s ' "$(quote "$arg")"
  done
}

# FIXME: Reset stdin.
read_confirm() {
  while :; do
    IFS= read -rsn 1 answer
    if [[ $answer =~ ^(Y|y| )$ || -z $answer ]]; then
      return 0
    elif [[ $answer =~ ^(N|n|$'\e')$ ]]; then
      return 1
    fi
  done
}

confirm() {
  echo -n "$1 [Y/n] "
  read_confirm
  ret=$?
  echo -n $'\b\b\b\b\b\b'
  (( ret )) && echo "No.  " || echo "Yes. "
  return $ret
} >&2

run() {
  if [[ $1 == not && $2 == nix-prefetch ]]; then
    shift # not
    shift # nix-prefetch
    ! nix-prefetch "$@"
  elif [[ $1 == nix-prefetch ]]; then
    shift # nix-prefetch
    nix-prefetch "$@"
  else
    echo "invalid command: $*" >&2
  fi
}

run-test() {
  if (( ${#script_args} > 0 )); then
    [[ $* == "${script_args[*]}" ]] && script_args=() || return 0
  fi
  while :; do
    echo "testing... $*"
    if run "$@" >&2; then
      echo "$(quote_args "$@")... succeeded!"
      break
    else
      echo "$(quote_args "$@")... failed!"
      confirm "Do you want to retry?" || break
    fi
  done
}

nix-prefetch() {
  # Allow the source to be used directly when developing.
  # To prevent `--subst-var-by bin` from replacing the string literal in the equality check,
  # the string literal for it has been broken up.
  if [[ $bin == '@''bin''@' ]]; then
    case $PWD in
      */nix-prefetch/src) ./main.sh "$@";;
      */nix-prefetch/lib) ../src/main.sh "$@";;
      */nix-prefetch) ./src/main.sh "$@";;
      *) die "The tests script for nix-prefetch called from an unsupported location: $PWD."
    esac
  else
    $bin/nix-prefetch "$@"
  fi
}

run-test nix-prefetch --list
run-test nix-prefetch --list --deep
run-test nix-prefetch hello --autocomplete
run-test not nix-prefetch
run-test nix-prefetch fetchFromGitHub --help
run-test nix-prefetch hello
run-test nix-prefetch hello --hash-algo sha512
run-test nix-prefetch hello.src
run-test nix-prefetch 'let name = "hello"; in pkgs.${name}'
run-test nix-prefetch 'callPackage (pkgs.path + /pkgs/applications/misc/hello) { }'
run-test nix-prefetch --file 'builtins.fetchTarball "channel:nixos-unstable"' hello
run-test not nix-prefetch hello 0000000000000000000000000000000000000000000000000000
run-test nix-prefetch hello_rs.cargoDeps
run-test nix-prefetch hello_rs.cargoDeps --fetcher '<nixpkgs/pkgs/build-support/rust/fetchcargo.nix>'
run-test nix-prefetch rsync --index 0
run-test nix-prefetch fetchurl --url mirror://gnu/hello/hello-2.10.tar.gz
run-test nix-prefetch '{ pkgs ? import <nixpkgs> { } }: pkgs.fetchurl' --url mirror://gnu/hello/hello-2.10.tar.gz
run-test nix-prefetch kore --fetchurl
run-test nix-prefetch fetchhg --input nix <<< '{
  url = "https://bitbucket.com/zck/2048.el";
  rev = "ea6c3bce8ac1";
  sha256 = "1p9qn9n8mfb4z62h1s94mlg0vshpzafbhsxgzvx78sqlf6bfc80l";
}'
run-test nix-prefetch hello --output expr
run-test nix-prefetch hello --output nix
run-test nix-prefetch hello --output json
run-test nix-prefetch hello --output shell
run-test nix-prefetch --help
run-test nix-prefetch --version

