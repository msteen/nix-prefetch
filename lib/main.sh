#!/usr/bin/env bash

## ##
## Configuration
## ##

case $(realpath .) in
  /nix/store/*) lib='@lib@';;
  */nix-prefetch/lib) lib='.';;
  */nix-prefetch) lib='./lib';;
  *) lib='@lib@';;
esac

version='@version@'

## ##
## Helper functions
## ##

trap 'exit "$exit_code"' SIGHUP
exit_code=0
pid=$$

exit_script() {
  exit_code=$?
  (( $# >= 1 )) && exit_code=$1
  kill -SIGHUP -- "$pid"
}

die() {
  (( ! silent )) && printf 'error: %s\n' "$*" >&2
  exit_script 1
}

die_help() {
  (( ! quiet )) && show_usage && printf '\n' >&2
  die "$@"
}

issue() {
  (( ! silent )) && printf '%s\nPlease report an issue at: %s\n' "$*" 'https://github.com/msteen/nix-prefetch/issues' >&2
  exit_script 1
}

quote() {
  grep -q '^[a-zA-Z0-9_]\+$' <<< "$*" && printf '%s' "$*" || printf '%s' "'${*//'/\\'}'"
}

unindent() {
  local indent
  indent=$(awk '
    { gsub(/\t/, "  ", $0); match($0, /^ */) }
    min == 0 || RLENGTH < min { min = RLENGTH }
    END { print min }
  ' <<< "$*")
  awk '{
    match($0, /^[ \t]*/);
    whitespace = substr($0, 0, RLENGTH);
    gsub(/\t/, "  ", whitespace);
    print substr(whitespace, '"$indent"' + 1) substr($0, RLENGTH + 1);
  }' <<< "$*"
}

print_assign() {
  printf '> %s=%s\n' "$1" "$(quote "$2")" >&2
}

print_vars() {
  for var in $*; do
    [[ -v $var ]] && print_assign "$var" "${!var}"
  done
}

print_bash_vars() {
  printf 'The following Bash variables have been set:\n%s\n\n' "$(print_vars "$1" 2>&1)" >&2
}

print_nix_eval() {
  printf 'The following Nix function call will be evaluated:\n%s\n\n' "$({ head -1; unindent "$(cat)"; } <<< "$1 $2" | sed 's/^/> /')" >&2
}

nix_bool() {
  local x=$*
  [[ -z $x || $x == 0 ]] && echo false || {
    [[ $x == 1 ]] && echo true || issue "Cannot convert '$x' to a Nix boolean."
  }
}

nix_str() {
  local x=$*
  nix-instantiate --eval --expr '{ str }: str' --argstr str "$x" || issue "Cannot convert '$x' to a Nix string."
}

nix_typed() {
  local type=$1 raw=$2
  case $type in
    file) value="($raw)";;
    attr) value="pkgs: with pkgs; ($raw); name = $(nix_str "$raw")";;
    expr) value="pkgs: with pkgs; ($raw)";;
     str) value=$(nix_str "$raw");;
       *) die_help "Unsupported expression type '$type'.";;
  esac
  printf '{ type = "%s"; value = %s; }' "$type" "$value"
}

handle_silent() {
  (( silent )) && exec 2> /dev/null
}

show_trace() {
  (( debug )) && echo --show-trace
}

nix_eval() {
  nix eval "$1" "(
    with $args_nix;
    with import $lib/pkgs.nix { inherit nixpkgsPath; };
    $2
  )" $(show_trace)
}

nix_call() {
  (( verbose )) && print_nix_eval "$1" "$args_nix"
  nix_eval "$2" "$3"
}

## ##
## Command line arguments
## ##

die_extra_param() {
  die_help "An unexpected extra parameter '$1' has been given."
}

die_option_param() {
  die_help "The option '$arg' needs a parameter."
}

die_arg_count() {
  die_help "A wrong number of arguments has been given."
}

show_usage() {
  cat <<'EOF' >&2
Usage:
  nix-prefetch [(-f | --file) <file>] [(-A | --attr) <attr>] [(-E | --expr) <expr>] [(-i | --index) <index>]
               [(-F | --fetcher) (<file> | <attr>)] [--fetch-url]
               [(-t | --type | --hash-algo) <hash-algo>] [(-h | --hash) <hash>]
               [--input <input-type>] [--output <output-type>] [--print-path]
               [--no-hash] [--force] [-s | --silent] [-q | --quiet] [-v | --verbose] [-vv | --debug] ...
               ([-f | --file] <file> | [-A | --attr] <attr> | [-E | --expr] <expr> | <url>) [<hash>]
               [--] [--<name> ((-f | --file) <file> | (-A | --attr) <attr> | (-E | --expr) <expr> | <str>) | --autocomplete <word> | --help] ...
  nix-prefetch [(-f | --file) <file>] [--deep] [-s | --silent] [-v | --verbose] [-vv | --debug] ... (-l | --list)
  nix-prefetch --help
  nix-prefetch --version
EOF
}

show_help() {
  man nix-prefetch
}

show_version() {
  echo "$version"
}

# Each command should be handled differently and to prevent issues like determinig their priorities,
# we do not allow them to be mixed, so e.g. calling adding --version while also having other arguments,
# will just result in the help message being shown with an error code.
(( $# == 1 )) &&
case $1 in
  --help)
    show_help
    exit
    ;;
  --version)
    show_version
    exit
    ;;
esac

# We need to be able to differentiate the remaining commands,
# because they will have different arguments available to them.
for arg in "$@"; do
  case $arg in
    -l|--list)
      file='<nixpkgs>'
      while (( $# >= 1 )); do
        arg=$1; shift
        case $arg in
          -f|--file)
            (( $# >= 1 )) || die_option_param
            file=$1
            ;;
          --deep) deep=1;;
          -s|--silent)  silent=1; verbose=0;;
          -v|--verbose) silent=0; verbose=1;;
          -vv|--debug)  silent=0; verbose=1; debug=1;;
          *) [[ $arg =~ ^(-l|--list)$ ]] || die_extra_param "$arg";;
        esac
      done
      handle_silent
      (( verbose )) && print_bash_vars 'file deep verbose debug'
      args_nix="{
        nixpkgsPath = ($file);
        deep = $(nix_bool "$deep");
      }"
      nix_call 'listFetchers' --raw "(
        with lib;
        lines (import $lib/list-fetchers.nix { inherit lib pkgs deep; })
      )"
      exit
    ;;
  esac
done

file='<nixpkgs>'
output_type=raw
while (( $# >= 1 )); do
  arg=$1; shift
  param=
  case $arg in
    -f|--file) param='file'; expr_type='file';;
    -A|--attr) param='expr'; expr_type='attr';;
    -E|--expr) param='expr'; expr_type='expr';;
    -i|--index) param='index';;
    -F|--fetcher) param='fetcher';;
    -t|--type|--hash-algo) param='hash_algo';;
    -h|--hash) param='hash';;
    --input) param='input_type';;
    --output) param='output_type';;
    --fetch-url|--print-path|--force|--no-hash|--help)
      var=${arg#--}
      var=${var//-/_}
      declare "${var}=1"
      ;;
    -s|--silent)  silent=1; quiet=1; verbose=0; debug=0;;
    -q|--quiet)   silent=0; quiet=1; verbose=0; debug=0;;
    -v|--verbose) silent=0; quiet=0; verbose=1;;
    -vv|--debug)  silent=0; quiet=0; verbose=1; debug=1;;
    --) break;;
    *)
      if [[ $arg == -* ]]; then
        set -- "$arg" "$@" # i.e. unshift
        break
      fi
      if (( arg_count == 0 )); then
        expr=$arg
        if [[ $arg == *://* ]]; then
          expr_type='url'
        elif [[ $arg == */* && -e $arg || $arg == '<'* ]]; then
          expr_type='file'
        elif [[ $arg =~ ^[a-zA-Z0-9_\-]+(\.[a-zA-Z0-9_\-]+)*$ ]]; then
          expr_type='attr'
        else
          expr_type='expr'
        fi
      elif (( arg_count == 1 )); then
        hash=$arg
      else
        die_extra_param "$arg"
      fi
      (( arg_count++ ))
      ;;
  esac
  if [[ -n $param ]]; then
    (( $# >= 1 )) || die_option_param
    declare "${param}=${1}"; shift
  fi
done

handle_silent

if [[ -v fetcher ]]; then
  [[ $fetcher == */* && -e $fetcher || $fetcher == '<'* ]] && type='file' || type='str'
  fetcher=$(nix_typed "$type" "$fetcher")
fi

declare -A fetcher_args

# An expression containing an URL is just syntax sugar
# for calling fetchurl with the URL passed as a fetcher argument.
if [[ $expr_type == url ]]; then
  fetcher_args[url]=$expr
  expr='fetchurl'
  expr_type='expr'
fi

# When no other expressions are given but the file, set the file to be the expression,
# because then it ought to point to either a fetcher function or package derivation.
if [[ -v file && ! -v expr ]]; then
  expr=$file
  file='<nixpkgs>' # reset to the default
fi

# The remaining arguments are passed to the fetcher.
while (( $# >= 2 )) && [[ $1 == --* ]]; do
  name=$1; name=${name#--*}; shift
  case $name in
    autocomplete)
      (( $# >= 1 )) || die_option_param
      autocomplete=$1; shift
      ;;
    help) help=1;;
    *) false;;
  esac && continue
  type='str'
  value=$1; shift
  case $value in
    -f|--file) type='file';;
    -A|--attr) type='attr';;
    -E|--expr) type='expr';;
    *) false;;
  esac && {
    (( $# >= 1 )) || break
    value=$1; shift
  }
  fetcher_args[$name]=$(nix_typed "$type" "$value")
done

if [[ -n $input_type ]]; then
  input=$(< /dev/stdin)
  if [[ $input_type == nix ]]; then
    input=$(nix-instantiate --eval --strict --expr "{ args }: with import $lib/lib.nix; toShell args" --arg args "$input" $(show_trace) | jq --raw-output '.') || exit
  elif [[ $input_type == json ]]; then
    input=$(jq --raw-output 'to_entries | .[] | .key + "=" + .value' <<< "$input") || exit
  fi
  while IFS= read -r line; do
    [[ $line == *'='* ]] || die "Expected a name value pair seperated by an equal sign, yet got input line '$line'."
    IFS='=' read -r name value <<< "$line"
    fetcher_args[$name]=$(nix_expr 'str' "$value")
  done <<< "$input"
fi

if (( verbose )); then
  printf '%s\n' "$(print_bash_vars 'file expr index fetcher hash hash_algo input_type output_type fetch_url print_path force quiet verbose debug skip_hash help' 2>&1)" >&2
  for name in "${!fetcher_args[@]}"; do
    value=${fetcher_args[$name]}
    print_assign "fetcher_args[$name]" "$value"
  done
  echo >&2
fi

(( $# == 0 )) || die_help "Finished parsing the command line arguments, yet still found the following arguments remaining:$( for arg in "$@"; do printf ' %s' "$(quote "$arg")"; done )."
[[ -v expr_type ]] || die_help "At least a file, attribute, expression, or URL should have been given."

expr=$(nix_typed "$expr_type" "$expr")

fetcher_args_nix='{'
for name in "${!fetcher_args[@]}"; do
  value=${fetcher_args[$name]}
  fetcher_args_nix+=$'\n    '"$name = $value;"
done
[[ $fetcher_args_nix != '{' ]] && fetcher_args_nix+=$'\n  '
fetcher_args_nix+='}'

args_nix="{
  nixpkgsPath = ($file);
  expr = $expr;
  index = $( [[ -v index ]] && echo "$index" || echo null );
  fetcher = $( [[ -v fetcher ]] && echo "$fetcher" || echo null );
  fetcherArgs = $fetcher_args_nix;
  hashAlgo = $( [[ -v hash_algo ]] && nix_str "$hash_algo" || echo null );
  hash = $( [[ -v hash ]] && nix_str "$hash" || echo null );
  fetchURL = $(nix_bool "$fetch_url");
}"

fetcher_autocomplete() {
  out=$(nix_call 'fetcherAutocomplete' --raw "(
    with import $lib/fetcher.nix { inherit lib pkgs expr index fetcher; };
    with lib;
    lines' (filter (hasPrefix $(nix_str "$autocomplete")) (attrNames (import $lib/fetcher-function-args.nix { inherit lib pkgs fetcher; })))
  )") || exit
  [[ -n $out ]] && printf '%s\n' "$out" || exit 1
}

fetcher_help() {
  nix_call 'fetcherHelp' --raw "(
    with import $lib/fetcher.nix { inherit lib pkgs expr index fetcher; };
    import $lib/fetcher-help.nix { inherit lib pkgs pkg fetcher; }
  )"
}

die_require_file() {
  read -r url name < <(jq --raw-output '.output | [.url, .name] | @tsv' <<< "$out")
  cat <<EOF >&2
Unfortunately the file $output cannot be downloaded automatically.
Please go to $url to download the file and add it to the Nix store like so:
nix-store --add-fixed $hash_algo $name
EOF
  exit 1
}

issue_no_hash_mismatch() {
  issue "A probably-wrong output hash of zeroes has been used, yet it somehow still succeeded in building."
}

hash_from_err() {
  # The hash mismatch error message has changed in version 2.2 of Nix,
  # swapping the order of the reported hashes.
  # https://github.com/NixOS/nix/commit/5e6fa9092fb5be722f3568c687524416bc746423
  if ! actual_hash=$(grep --only-matching "[a-z0-9]\{${actual_hash_size}\}" <<< "$err" > >( [[ $err == *'instead of the expected hash'* ]] && head -1 || tail -1 )); then
    [[ -n $out ]] && echo "$out" >&2
    [[ -n $err ]] && echo "$err" >&2
    issue "The only expected error message is that of a hash mismatch, yet the grep for it failed."
  fi
}

hash_builtin() {
  err=$(nix_eval --raw "(
    with import $lib/fetcher.nix { inherit lib pkgs expr index fetcher; };
    with import $lib/prefetcher.nix { inherit lib pkgs pkg fetcher fetcherArgs hashAlgo hash fetchURL; };
    (with prefetcher; fun (args // { ${hash_algo} = probablyWrongHashes.${hash_algo}; })).drvPath
  )" 2>&1) && issue_no_hash_mismatch || hash_from_err
}

hash_generic() {
  # Try to determine whether the current hash is already valid,
  # so that we do not have to fetch the sources unnecessarily.
  if (( ! force )); then
    # Due to `nix-store --query --deriver` not giving back anything useful (see: https://github.com/NixOS/nix/issues/2631),
    # the only approximiation of whether a hash is already valid is to check if its been rooted in the Nix store.
    # The assumption being made here is that you won't keep a package with an outdated hash rooted in the Nix store,
    # i.e. you won't keep an updated package with an oudated source installed.
    outputs=$(while IFS= read -r p; do [[ -e $p ]] && printf '%s\n' "$p"; done < <(nix-store --query --outputs $(nix-store --query --referrers "$drv_path")))
    [[ -n $outputs ]] && while IFS= read -r root; do
      if [[ $(basename "$root") != result ]]; then
        actual_hash=$expected_hash
        return
      fi
    done < <(nix-store --query --roots $outputs)
  fi

  err=$(nix-store --quiet --realize "$wrong_drv_path" 2>&1) && issue_no_hash_mismatch || hash_from_err
}

prefetch() {
  out=$(nix_call 'prefetch' --json "(
    with import $lib/fetcher.nix { inherit lib pkgs expr index fetcher; };
    with import $lib/prefetcher.nix { inherit lib pkgs pkg fetcher fetcherArgs hashAlgo hash fetchURL; };
    json
  )") || exit

  if ! vars=$(jq --raw-output '.bash_vars | to_entries | .[] | .key + "=" + .value' <<< "$out"); then
    [[ -n $out ]] && echo "$out" >&2
    issue "The Nix code was unable to produce valid JSON."
  fi
  while IFS= read -r var; do declare "$var"; done <<< "$vars"
  (( verbose )) && print_bash_vars "$(jq --raw-output '.bash_vars | keys | join(" ")' <<< "$out")"

  [[ $fetcher != requireFile ]] || die_require_file

  log=$(jq --raw-output '.log' <<< "$out")
  (( ! quiet )) && [[ -n $log ]] && echo "$log" >&2 && echo >&2

  if (( no_hash )); then
    actual_hash=$expected_hash
  elif [[ $fetcher == builtins.* ]]; then
    hash_builtin
  else
    hash_generic
  fi

  if (( check_hash )) && [[ $expected_hash != "$actual_hash" ]]; then
    die "$(printf "A hash mismatch occurred for the fixed-output derivation output %s:\n  expected: %s\n    actual: %s" "$output" "$expected_hash" "$actual_hash")"
  fi

  [[ $output_type == raw ]] || json=$(jq --raw-output '.fetcher_args | .'"$hash_algo"' = "'"$actual_hash"'"' <<< "$out")
  case $output_type in
    expr) printf '%s\n' "(
  with $(awk 'NR > 1 { printf "  " } { print }' <<< "$args_nix");
  with import $lib/pkgs.nix { inherit nixpkgsPath; };
  with import $lib/fetcher.nix { inherit lib pkgs expr index fetcher; };
  with import $lib/prefetcher.nix { inherit lib pkgs pkg fetcher fetcherArgs hashAlgo hash fetchURL; };
  { inherit pkgs fetcher prefetcher; }
)";;
    nix) nix-instantiate --eval --strict --expr '{ json }: builtins.fromJSON json' --argstr json "$json";;
    json) echo "$json";;
    shell) jq --raw-output 'to_entries | .[] | .key + "=" + .value' <<< "$json";;
    raw) echo "$actual_hash";;
  esac

  if (( print_path )); then
    [[ $output_type == raw ]] || die "The print path option only works with the default raw output."
    if [[ $fetcher == builtins.* ]]; then
      output=$(nix_eval --raw "(
        with import $lib/fetcher.nix { inherit lib pkgs expr index fetcher; };
        with import $lib/prefetcher.nix { inherit lib pkgs pkg fetcher fetcherArgs hashAlgo hash fetchURL; };
        (with prefetcher; fun (args // { ${hash_algo} = \"${actual_hash}\"; })).out
      )") || exit
    fi
    echo "$output"
  fi
}

if (( help )); then
  fetcher_help
elif [[ -n $autocomplete ]]; then
  fetcher_autocomplete
else
  prefetch
fi
