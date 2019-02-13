#!/usr/bin/env bash

file_args=( "$@" )

quote() {
  grep -q '^[a-zA-Z0-9_\.-]\+$' <<< "$*" && printf '%s' "$*" || printf '%s' "'${*//'/\\'}'"
}

quote_args() {
  for arg in "$@"; do
    printf '%s ' "$(quote "$arg")"
  done
}

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
  if (( ${#file_args} > 0 )); then
    [[ $* == "${file_args[*]}" ]] && file_args=() || return 0
  fi
  while :; do
    echo "testing... $*"
    if run "$@" >&2; then
      echo "$(quote_args "$@")... succeeded!"
      confirm "Do you want to continue with the next test?" && break || exit 0
    else
      echo "$(quote_args "$@")... failed!"
      confirm "Do you want to retry?" || {
        confirm "Do you want to continue with the next test?" && break || exit 1
      }
    fi
  done
}

nix-prefetch() {
  case $(realpath .) in
    */nix-prefetch/lib) ./main.sh "$@";;
    */nix-prefetch) ./lib/main.sh "$@";;
    *) command nix-prefetch "$@";;
  esac
}

run-test nix-prefetch --list
run-test nix-prefetch --list --deep
run-test nix-prefetch hello --help
run-test nix-prefetch hello
run-test nix-prefetch hello --hash-algo sha512
run-test nix-prefetch hello.src
run-test nix-prefetch 'let name = "hello"; in pkgs.${name}'
run-test nix-prefetch 'callPackage (pkgs.path + /pkgs/applications/misc/hello) { }'
run-test nix-prefetch --file 'builtins.fetchTarball "channel:nixos-unstable"' hello
run-test not nix-prefetch hello 0000000000000000000000000000000000000000000000000000
run-test nix-prefetch du-dust.cargoDeps
run-test nix-prefetch du-dust.cargoDeps --fetcher '<nixpkgs/pkgs/build-support/rust/fetchcargo.nix>'
run-test nix-prefetch openraPackages.mods.ca --index 0 --rev master
run-test nix-prefetch fetchurl --url mirror://gnu/hello/hello-2.10.tar.gz
run-test nix-prefetch '{ name ? "fetchurl" }: pkgs.${name}' --url mirror://gnu/hello/hello-2.10.tar.gz
run-test nix-prefetch hello --output expr
run-test nix-prefetch hello --output nix
run-test nix-prefetch hello --output json
run-test nix-prefetch hello --output shell
run-test nix-prefetch --help
run-test nix-prefetch --version
