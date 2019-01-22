#!/usr/bin/env bash

## ##
## Configuration

lib='@lib@'
version='@version@'

## ##
## Helper functions

print_args() {
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
}

print_assign() {
  printf '> %s=%q\n' "$1" "$2" >&2
}

print_vars() {
  for var in $*; do
    [[ -v $var ]] && print_assign "$var" "${!var}"
  done
}

print_cli_vars() {
  echo "Based on the arguments, the following Bash variables have been set:" >&2
  print_vars "$1"
}

print_nix_args() {
  echo "Based on the arguments, the Nix component will be run as follows:" >&2
  sed 's/^/> /' <<< "$1 $2" >&2
  echo >&2
}

nix_bool() {
  local x=$*
  if [[ -z $x || $x == 0 ]]; then printf false
  elif [[ $x == 1 ]]; then printf true
  else echo "Cannot convert '$x' to Nix boolean." >&2 && exit 1
  fi
}

nix_str() {
  nix-instantiate --eval --expr '{ str }: str' --argstr str "$*"
}

nix_expr() {
  local type=$1 expr=$2
  case $type in
    file) expr="($expr)";;
    attr) expr="pkgs: (pkgs.$expr)";;
    expr) expr="pkgs: (with pkgs; $expr)";;
     str) expr=$(nix_str "$expr")
  esac
  printf '{ type = "%s"; expr = %s; }' "$type" "$expr"
}

issue() {
  echo "Something unexpected happened:" >&2
  echo "$*" >&2
  echo "Please report an issue at: https://github.com/msteen/nix-prefetch/issues" >&2
  exit 1
}

## ##
## Secondary commands

list_fetchers() {
  if (( verbose )); then
    print_cli_vars 'file deep'
    echo >&2
  fi
  nixArgs="{
  inherit lib;
  file = toExpr ($file);
  deep = $(nix_bool "$deep");
}"
  (( verbose )) && print_nix_args 'listFetchers' "$nixArgs"
  (( debug )) && nix_eval_args=( --show-trace )
  nix eval --raw "(let lib = import $lib/lib.nix; in with lib; import $lib/list-fetchers.nix $nixArgs)" "${nix_eval_args[@]}"
}

show_help() {
  normal=$1
  cat <<'EOF' > "/dev/std$( (( normal )) && echo out || echo err )"
Prefetch any fetcher function call, e.g. a package source.

All options can be repeated with the last value taken,
and can placed both before and after the parameters.

Usage:
  nix-prefetch [ -f <file> | --file <file>
               | -A <attr> | --attr <attr>
               | -E <expr> | --expr <expr>
               | -i <index> | --index <index>
               | -F (<file> | <attr>) | --fetcher (<file> | <attr>)
               | -t <hash-algo> | --type <hash-algo> | --hash-algo <hash-algo>
               | -h <hash> | --hash <hash>
               | --fetch-url | --print-path | --force
               | -q | --quiet | -v | --verbose | -vv | --debug | --skip-hash ]...
               ( -f <file> | --file <file> | <file>
               | -A <attr> | --attr <attr> | <attr>
               | -E <expr> | --expr <expr> | <expr>
               | <url> )
               [hash]
               [--]
               [ --<name>
                 ( -f <file> | --file <file>
                 | -A <attr> | --attr <attr>
                 | -E <expr> | --expr <expr>
                 | <str> ) ]...
  nix-prefetch [-f <file> | --file <file> | --deep | -v | --verbose | -vv | --debug]... (-l | --list)
  nix-prefetch --help
  nix-prefetch [-v | --verbose | -vv | --debug] (-f <file> | --file <file> | <attr>) --help
  nix-prefetch --version

Examples:
  nix-prefetch hello
  nix-prefetch hello --hash-algo sha512
  nix-prefetch hello.src
  nix-prefetch 'let name = "hello"; in pkgs.${name}'
  nix-prefetch 'callPackage (pkgs.path + /pkgs/applications/misc/hello) { }'
  nix-prefetch --file '<nixos-unstable>' hello
  nix-prefetch hello 0000000000000000000000000000000000000000000000000000
  nix-prefetch du-dust.cargoDeps --fetcher --file '<nixpkgs/pkgs/build-support/rust/fetchcargo.nix>'

Options:
  -f, --file       When either an attribute or expression is given it has to be a path to Nixpkgs,
                   otherwise it can be a file directly pointing to a fetcher function or package derivation.
  -A, --attr       An attribute path relative to the `pkgs` of the imported Nixpkgs.
  -E, --expr       A Nix expression with the `pkgs` of the imported Nixpkgs put into scope,
                   evaluating to either a fetcher function or package derivation.
  -i, --index      Which element of the list of sources should be used when multiple sources are available.
  -F, --fetcher    When the fetcher of the source cannot be automatically determined,
                   this option can be used to pass it manually instead.
  -t, --type,
      --hash-algo  What algorithm should be used for the output hash of the resulting derivation.
  -h, --hash       When the output hash of the resulting derivation is already known,
                   it can be used to check whether it is already exists within the Nix store.
  --fetch-url      Fetch only the URL. This converts e.g. the fetcher fetchFromGitHub to fetchurl for its URL,
                   and the hash options will be applied to fetchurl instead. The name argument will be copied over.
  --print-path     Print the output path of the resulting derivation.
  --force          Always redetermine the hash, even if the given hash is already determined to be valid.
  -q, --quiet      No additional output.
  -v, --verbose    Verbose output, so it is easier to determine what is being done.
  -vv, --debug     Even more verbose output (meant for debugging purposes).
  --skip-hash      Skip determining the hash (meant for debugging purposes).
  --deep           Rather than only listing the top-level fetchers, deep search Nixpkgs for fetchers (slow).
  -l, --list       List the available fetchers in Nixpkgs.
  --version        Show version information.
  --help           Show help message.

Note: This program is EXPERIMENTAL and subject to change.
EOF
}

show_fetcher_help() {
  if (( verbose )); then
    print_cli_vars 'fetcher fetcher_is_file'
    echo >&2
  fi
  nixArgs="{
  inherit lib;
  fetcher = $( (( fetcher_is_file )) && echo "$fetcher" || nix_str "$fetcher" );
}"
  (( verbose )) && print_nix_args 'showFetcherHelp' "$nixArgs"
  (( debug )) && nix_eval_args=( --show-trace )
  nix eval --raw "(let lib = import $lib/lib.nix; in with lib; import $lib/show-fetcher-help.nix $nixArgs)" "${nix_eval_args[@]}"
}

show_version() {
  echo "$version"
}

## ##
## Command line arguments

die() {
  echo "Error: $*" >&2
  exit 1
}

die_help() {
  show_help 0
  echo >&2
  die "$@"
}

die_extra_param() {
  die_help "An unexpected extra parameter '$1' has been given."
}

die_option_param() {
  die_help "The option '$1' needs a parameter."
}

die_arg_count() {
  die_help "A wrong number of arguments has been given."
}

# Each command should be handled differently and to prevent issues like determinig their priorities,
# we do not allow them to be mixed, so e.g. calling adding --version while also having other arguments,
# will just result in the help message being shown with an error code.
(( $# == 1 )) &&
case $1 in
  --help)
    show_help 1
    exit
    ;;
  --version)
    show_version
    exit
    ;;
esac

# We need to be able to differentiate the remaining commands,
# because they will have different arguments available to them.
cmd=prefetch
for arg in "$@"; do
  case $arg in
    -l|--list)
      file='<nixpkgs>'
      while (( $# >= 1 )); do
        arg=$1 && shift
        case $arg in
          -f|--file)
            (( $# >= 1 )) || die_option_param 'file'
            file=$1
            ;;
          --deep) deep=1;;
          -vv|--debug) debug=1 && verbose=1;;
          *) [[ $arg =~ ^(-l|--list)$ ]] || die_extra_param "$arg";;
        esac
      done
      list_fetchers
      exit
    ;;
    --help)
      while (( $# >= 1 )); do
        arg=$1 && shift
        case $arg in
          -vv|--debug) debug=1 && verbose=1;;
          --help) continue;;
          -f|--file)
            (( $# >= 1 )) || die_option_param 'file'
            fetcher=$1 && fetcher_is_file=1 && shift
            ;;
          *)
            (( ! arg_count )) || die_extra_param "$arg"
            fetcher=$arg
            (( arg_count++ ))
            ;;
        esac
      done
      [[ -v fetcher ]] || die_help "At least a file or attribute should have been given."
      show_fetcher_help
      exit
    ;;
  esac
done

file='<nixpkgs>'
while (( $# >= 1 )); do
  arg=$1 && shift
  case $arg in
    -f|--file)
      (( $# >= 1 )) || die_option_param 'file'
      file=$1 && expr_type=file && shift
      ;;
    -A|--attr)
      (( $# >= 1 )) || die_option_param 'attr'
      expr=$1 && expr_type=attr && shift
      ;;
    -E|--expr)
      (( $# >= 1 )) || die_option_param 'expr'
      expr=$1 && expr_type=expr && shift
      ;;
    -i|--index)
      (( $# >= 1 )) || die_option_param 'index'
      index=$1 && shift
      ;;
    -F|--fetcher)
      (( $# >= 1 )) || die_option_param 'fetcher'
      fetcher=$1 && shift
      [[ $fetcher == */* && -e $fetcher || $fetcher == '<'* ]] && fetcher_is_file=1
      ;;
    -t|--type|--hash-algo)
      (( $# >= 1 )) || die_option_param 'hash_algo'
      hash_algo=$1 && shift
      ;;
    -h|--hash)
      (( $# >= 1 )) || die_option_param 'hash'
      hash=$1 && shift
      ;;
    --fetch-url) fetch_url=1;;
    --print-path) print_path=1;;
    --force) force=1;;
    --q|--quiet) quiet=1;;
    -v|--verbose) verbose=1;;
    -vv|--debug) debug=1 && verbose=1;;
    --skip-hash) skip_hash=1;;
    --) break;;
    *)
      if [[ $arg == -* ]]; then
        set -- "$arg" "$@" # i.e. unshift
        break
      fi
      if (( arg_count == 0 )); then
        expr=$arg
        if [[ $arg == *://* ]]; then
          expr_type=url
        elif [[ $arg == */* && -e $arg || $arg == '<'* ]]; then
          expr_type=file
        elif [[ $arg =~ ^[a-zA-Z0-9_\-]+(\.[a-zA-Z0-9_\-]+)*$ ]]; then
          expr_type=attr
        else
          expr_type=expr
        fi
      elif (( arg_count == 1 )); then
        hash=$arg
      else
        die_extra_param "$arg"
      fi
      (( arg_count++ ))
      ;;
  esac
done

[[ -v expr_type ]] || die_help "At least a file, attribute, expression, or URL should have been given."

declare -A fetcher_args

# An expression containing an URL is just syntax sugar
# for calling fetchurl with the URL passed as a fetcher argument.
if [[ $expr_type == url ]]; then
  fetcher_args[url]=$expr
  expr=fetchurl
  expr_type=expr
fi

# The remaining arguments are passed to the fetcher function.
while (( $# >= 2 )) && [[ $1 == --* ]]; do
  name=$1 && name=${name#--*} && shift
  type=str
  value=$1 && shift
  case $value in
    -f|--file) type=file;;
    -A|--attr) type=attr;;
    -E|--expr) type=expr;;
    *) false;;
  esac && {
    (( $# >= 1 )) || break
    value=$1 && shift
  }
  fetcher_args[$name]=$(nix_expr "$type" "$value")
done

# There should be no more arguments left if all arguments were valid.
(( $# == 0 )) || die_help "Finished parsing the command line arguments, yet still found the following arguments remaining:$(print_args "$@")."

# When no other expressions are given but the file, set the file to be the expression,
# because then it ought to point to either a fetcher function or package derivation.
if [[ -v file && ! -v expr ]]; then
  expr=$file
  file='<nixpkgs>' # reset to the default
fi

## ##
## Primary command

if (( verbose )); then
  print_cli_vars 'file expr expr_type index fetcher fetcher_is_file hash hash_algo fetch_url print_path force quiet verbose debug skip_hash'
  for name in "${!fetcher_args[@]}"; do
    value=${fetcher_args[$name]}
    print_assign "fetcher_args[$name]" "$value"
  done
  echo >&2
fi

expr=$(nix_expr "$expr_type" "$expr")

fetcherArgs='{'
for name in "${!fetcher_args[@]}"; do
  value=${fetcher_args[$name]}
  fetcherArgs+=$'\n    '"$name = $value;"
done
fetcherArgs+=$'\n  }'

nixArgs="{
  inherit lib;
  nixpkgsPath = ($file);
  expr = $expr;
  index = $( [[ -v index ]] && echo "$index" || echo null );
  fetcher = $( [[ -v fetcher ]] && { (( fetcher_is_file )) && echo "$fetcher" || nix_str "$fetcher"; } || echo null );
  fetcherArgs = $fetcherArgs;
  hashAlgo = $( [[ -v hash_algo ]] && nix_str "$hash_algo" || echo null );
  hash = $( [[ -v hash ]] && nix_str "$hash" || echo null );
  fetchURL = $(nix_bool "$fetch_url");
  quiet = $(nix_bool "$quiet");
  verbose = $(nix_bool "$verbose");
  debug = $(nix_bool "$debug");
}"

(( verbose )) && print_nix_args 'prefetch' "$nixArgs"

(( debug )) && nix_eval_args=( --show-trace )
raw=$(nix eval --raw "(let lib = import $lib/lib.nix; in with lib; import $lib/prefetch.nix $nixArgs)" "${nix_eval_args[@]}") || exit

# The raw output contains a log and the information about the resulting derivation of the fetcher.
vars='wrong_drv_path drv_path output expected_hash actual_hash_size check_hash'
IFS=':' read -r $vars < <(tail -1 <<< "$raw")
if [[ ! $check_hash =~ ^[01]$ ]]; then
  echo "$raw" >&2
  issue "The Nix component of the prefetcher should always return a valid line of information, yet it failed to produce one."
fi
head -n -1 <<< "$raw" >&2

if (( verbose )); then
  echo "Based on the response of the Nix component, the following Bash variables have been set:" >&2
  print_vars "$vars"
  echo >&2
fi

# When debugging something other than the hash for the prefetcher,
# we would prefer not to waste any time on actually determining the hash.
if (( ! skip_hash )); then
  # Try to determine whether the current hash is already valid,
  # so that we do not have to fetch the sources unnecessarily.
  if (( ! force )); then
    outputs=$(while IFS= read -r p; do [[ -e $p ]] && echo "$p"; done < <(nix-store --query --outputs $(nix-store --query --referrers $drv_path)))
    [[ -n $outputs ]] && while IFS= read -r root; do
      if [[ $(basename "$root") != result ]]; then
        actual_hash=$expected_hash
        break
      fi
    done < <(nix-store --query --roots $outputs)
  fi

  if [[ ! -v actual_hash ]]; then
    if err=$(nix-store --quiet --realize "$wrong_drv_path" 2>&1); then
      issue "A probably-wrong output hash of zeroes has been used, yet it somehow still succeeded in building."
    fi

    # The hash mismatch error message has changed in version 2.2 of Nix,
    # swapping the order of the reported hashes.
    # https://github.com/NixOS/nix/commit/5e6fa9092fb5be722f3568c687524416bc746423
    if ! actual_hash=$(grep --only-matching "[a-z0-9]\{$actual_hash_size\}" <<< "$err" > >( [[ $err == *'hash mismatch'* ]] && tail -1 || head -1 )); then
      echo "$err" >&2
      issue "The only expected error message is that of a hash mismatch, yet the grep for it failed."
    fi
  fi

  if (( check_hash )) && [[ $expected_hash != "$actual_hash" ]]; then
    die "$(printf "A hash mismatch occurred for the fixed-output derivation output '%s':\n  expected: %s\n    actual: %s" "$output" "$expected_hash" "$actual_hash")"
  fi

  echo "$actual_hash"
fi

if (( print_path )); then
  echo "$output"
fi
