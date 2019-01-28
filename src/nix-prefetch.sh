#!/usr/bin/env bash

# Trust-On-First-Use (TOFU) is a security model that will trust that, the response given by the non-yet-trusted endpoint,
# is correct on first use and will derive an identifier from it to check the trustworthiness of future requests to the endpoint.
# An well-known example of this is with SSH connections to hosts that are reporting a not-yet-known host key.
# In the context of Nixpkgs, TOFU can be applied to fixed-output derivation (like produced by fetchers) to supply it with an output hash.
# https://en.wikipedia.org/wiki/Trust_on_first_use

# To implement the TOFU security model for fixed-output derivations the output hash has to determined at first build.
# This can be achieved by first supplying the fixed-output derivation with a probably-wrong output hash,
# that forces the build to fail with a hash mismatch error, which contains in its error message the actual output hash.

## ##
## Configuration

lib='@lib@'
version='@version@'

## ##
## Helper functions

die() {
  echo "error: $*" >&2
  exit 1
}

die_help() {
  show_help 0
  echo >&2
  die "$@"
}

quote() {
  grep -q '^[a-zA-Z0-9_]\+$' <<< "$*" && echo "$*" || echo "'$(sed "s/'/\\\\'/" <<< "$*")'"
}

print_args() {
  for arg in "$@"; do
    printf ' %s' "$(quote "$arg")"
  done
}

print_assign() {
  printf '> %s=%s\n' "$1" "$(quote "$2")" >&2
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

print_nix_eval_args() {
  echo "Based on the arguments, the Nix component will be run as follows:" >&2
  local nix="$1 $2"
  local n=$(grep -o '\( *\)' <(tail -1 <<< "$nix") | tr -d '\n' | wc -c)
  { (( n )) && sed "s/^[ ]\{$n\}?/> /" || sed 's/^/> /'; } <<< "$nix" >&2
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
  listFetchersArgs="{
    nixpkgsPath = ($file);
    deep = $(nix_bool "$deep");
  }"
  (( verbose )) && print_nix_eval_args 'listFetchers' "$listFetchersArgs"
  (( debug )) && nix_eval_args=( --show-trace )
  nix eval --raw "(
    with $listFetchersArgs;
    with import $lib/lib-nixpkgs.nix nixpkgsPath;
    lines (listFetchers deep pkgs)
  )" "${nix_eval_args[@]}"
}

show_help() {
  normal=$1
  cat HELP > "/dev/std$( (( normal )) && echo out || echo err )"
}

show_version() {
  echo "$version"
}

## ##
## Command line arguments

die_extra_param() {
  die_help "An unexpected extra parameter '$1' has been given."
}

die_option_param() {
  die_help "The option '$1' needs a parameter."
}

die_arg_count() {
  die_help "A wrong number of arguments has been given."
}

set_fetcher() {
  local type expr
  if [[ $1 == */* && -e $1 || $1 == '<'* ]]; then
    local type=path expr=$1
  else
    local type=attr expr=$(nix_str "$1")
  fi
  fetcher=$(printf '{ type = "%s"; expr = %s; }' "$type" "$expr")
}

orig_args=( "$@" )

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

file='<nixpkgs>'

# We need to be able to differentiate the remaining commands,
# because they will have different arguments available to them.
for arg in "$@"; do
  case $arg in
    -l|--list)
      while (( $# >= 1 )); do
        arg=$1 && shift
        case $arg in
          -f|--file)
            (( $# >= 1 )) || die_option_param 'file'
            file=$1
            ;;
          --deep) deep=1;;
          -v|--verbose) verbose=1;;
          -vv|--debug) verbose=1 && debug=1;;
          *) [[ $arg =~ ^(-l|--list)$ ]] || die_extra_param "$arg";;
        esac
      done
      list_fetchers
      exit
    ;;
  esac
done

file='<nixpkgs>'
output_type=raw
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
      set_fetcher "$1" && shift
      ;;
    -t|--type|--hash-algo)
      (( $# >= 1 )) || die_option_param 'hash_algo'
      hash_algo=$1 && shift
      ;;
    -h|--hash)
      (( $# >= 1 )) || die_option_param 'hash'
      hash=$1 && shift
      ;;
    --input)
      (( $# >= 1 )) || die_option_param 'input'
      input_type=$1 && shift
      ;;
    --output)
      (( $# >= 1 )) || die_option_param 'output'
      output_type=$1 && shift
      ;;
    --with-position) with_position=1;;
    --diff) diff=1;;
    --fetch-url) fetch_url=1;;
    --print-path) print_path=1;;
    --force) force=1;;
    --q|--quiet) quiet=1 && verbose=0 && debug=0;;
    -v|--verbose) quiet=0 && verbose=1;;
    -vv|--debug) quiet=0 && verbose=1 && debug=1;;
    --skip-hash) skip_hash=1;;
    --help) help=1;;
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

if [[ -n $input_type ]]; then
  input=$(< /dev/stdin)
  if [[ $input_type == nix ]]; then
    input=$(nix-instantiate --eval --strict --expr "{ args }: with import $lib/lib.nix; toShell args" --arg args "$input" --show-trace | jq --raw-output '.') || exit
  elif [[ $input_type == json ]]; then
    input=$(jq --raw-output 'to_entries | .[] | .key + "=" + .value' <<< "$input") || exit
  fi
  while IFS= read -r line; do
    [[ $line == *'='* ]] || die "Invalid input '$line', expected a name value pair seperated by an equal sign."
    IFS='=' read -r name value <<< "$line"
    fetcher_args[$name]=$(nix_expr 'str' "$value")
  done <<< "$input"
fi

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

hash_from_err() {
  # The hash mismatch error message has changed in version 2.2 of Nix,
  # swapping the order of the reported hashes.
  # https://github.com/NixOS/nix/commit/5e6fa9092fb5be722f3568c687524416bc746423
  if ! actual_hash=$(grep --only-matching "[a-z0-9]\{$actual_hash_size\}" <<< "$err" > >( [[ $err == *'instead of the expected hash'* ]] && head -1 || tail -1 )); then
    [[ -n $out ]] && echo "$out" >&2
    [[ -n $err ]] && echo "$err" >&2
    issue "The only expected error message is that of a hash mismatch, yet the grep for it failed."
  fi
}

print_actual_hash() {
  if (( check_hash )) && [[ $expected_hash != "$actual_hash" ]]; then
    die "$(printf "A hash mismatch occurred for the fixed-output derivation output '%s':\n  expected: %s\n    actual: %s" "$output" "$expected_hash" "$actual_hash")"
  fi

  if [[ $output_type != raw ]]; then
    if (( diff )) && [[ $expected_hash == "$actual_hash" ]]; then
      output_jq='del(.'"$hash_algo"')'
    else
      (( with_position )) && output_jq='.'"$hash_algo"'.value = "'"$actual_hash"'"' || output_jq='.'"$hash_algo"' = "'"$actual_hash"'"'
    fi
    json=$(jq --raw-output '.output | '"$output_jq" <<< "$out")
  elif (( diff )); then
    die "Diff is not supported for raw output."
  fi

  case $output_type in
    raw) echo "$actual_hash";;
    shell) jq --raw-output 'to_entries | .[] | .key + "=" + .value' <<< "$json";;
    nix) nix-instantiate --eval --strict --expr '{ json }: builtins.fromJSON json' --argstr json "$json";;
    json) echo "$json";;
  esac
}

expr=$(nix_expr "$expr_type" "$expr")

fetcherArgs='{'
for name in "${!fetcher_args[@]}"; do
  value=${fetcher_args[$name]}
  fetcherArgs+=$'\n    '"$name = $value;"
done
[[ $fetcherArgs != '{' ]] && fetcherArgs+=$'\n  '
fetcherArgs+='}'

json_file=/tmp/nix-prefetch.$(date +%s%N).json

exprArgs="{
  writeFile = $lib/write_file.sh;
  jsonFile = $json_file;
  nixpkgsPath = ($file);
  expr = $expr;
  index = $( [[ -v index ]] && echo "$index" || echo null );
  fetcher = $( [[ -v fetcher ]] && echo "$fetcher" || echo null );
  fetcherArgs = $fetcherArgs;
  hashAlgo = $( [[ -v hash_algo ]] && nix_str "$hash_algo" || echo null );
  hash = $( [[ -v hash ]] && nix_str "$hash" || echo null );
  fetchURL = $(nix_bool "$fetch_url");
  withPosition = $(nix_bool "$with_position");
  diff = $(nix_bool "$diff");
  quiet = $(nix_bool "$quiet");
  verbose = $(nix_bool "$verbose");
  debug = $(nix_bool "$debug");
}"

(( verbose )) && print_nix_eval_args 'prefetch' "$exprArgs"
(( debug )) && nix_eval_args=( --show-trace )

if (( help )); then
  nix eval --raw "(import $lib/showFetcherHelp.nix $exprArgs)" "${nix_eval_args[@]}"
  exit
fi

nix_eval_args+=( --option allow-unsafe-native-code-during-evaluation true )

# https://unix.stackexchange.com/questions/430161/redirect-stderr-and-stdout-to-different-variables-without-temporary-files/430182#430182
{
  out=$(nix eval --json "(import $lib/prefetch.nix $exprArgs)" "${nix_eval_args[@]}" 2> /dev/fd/3)
  ret=$?
  err=$(cat <&3)
} 3<<EOF
EOF

if (( ret )); then
  if [[ -e $json_file && ($err == *'instead of the expected hash'* || $err == *'hash mismatch'*) ]]; then
    builtin_fetcher=1
    out=$(< "$json_file")
    rm "$json_file"
  else
    [[ -n $err ]] && echo "$err" >&2
    exit 1
  fi
fi

if ! vars=$(jq --raw-output '.bash_vars | to_entries | .[] | .key + "=" + .value' <<< "$out"); then
  [[ -n $out ]] && echo "$out" >&2
  [[ -n $err ]] && echo "$err" >&2
  issue "The Nix component of the prefetcher should always return a valid JSON response, yet it failed to produce one."
fi

while IFS= read -r var; do
  declare "$var"
done <<< "$vars"

log=$(jq --raw-output '.log' <<< "$out")
[[ -n $log ]] && printf '%s\n\n' "$log" >&2

if (( verbose )); then
  echo "Based on the response of the Nix component, the following Bash variables have been set:" >&2
  print_vars "$(jq --raw-output '.bash_vars | keys | join(" ")' <<< "$out")"
  echo >&2
fi

if [[ $fetcher == requireFile ]]; then
  read -r url name < <(jq --raw-output '[.output.url, .output.name] | @tsv' <<< "$out")
  # FIXME: Use orig_args to rebuild the suggested nix-prefetch call.
  cat <<EOF >&2
Unfortunately the file $output cannot be downloaded automatically.
Please go to $url to download the file and add it to the Nix store like so:
  nix-store --add-fixed $hash_algo $name
EOF
  exit 1
fi

if (( ! skip_hash )); then
  if (( builtin_fetcher )); then
    output='<unknown>'
    hash_from_err
  else
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
      hash_from_err
    fi
  fi
else
  actual_hash=$expected_hash
fi

print_actual_hash

if (( print_path )); then
  [[ $output_type == raw ]] || die "The print path option only works with the default raw output."
  echo "$output"
fi
