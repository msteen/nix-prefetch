#!/usr/bin/env bash

## ##
## Configuration
## ##

lib='@lib@'
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

# Allow the source to be used directly when developing.
# To prevent `--subst-var-by lib` from replacing the string literal in the equality check,
# the string literal for it has been broken up.
if [[ $lib == '@'lib'@' ]]; then
  case $PWD in
    */nix-prefetch/lib) lib=$PWD;;
    */nix-prefetch/src) lib=$(realpath "$PWD/../lib");;
    */nix-prefetch) lib=$PWD/lib;;
    *) die "The script backing nix-prefetch called from an unsupported location: $PWD."
  esac
fi

die_help() {
  (( ! quiet )) && { show_usage; printf '\n'; } >&2
  die "$@"
}

issue() {
  (( ! silent )) && printf '%s\nPlease report an issue at: %s\n' "$*" 'https://github.com/msteen/nix-prefetch/issues' >&2
  exit_script 1
}

quote() {
  grep -q '^[a-zA-Z0-9_\.-]\+$' <<< "$*" && printf '%s' "$*" || printf '%s' "'${*//'/\\'}'"
}

# https://stackoverflow.com/questions/6570531/assign-string-containing-null-character-0-to-a-variable-in-bash
quote_nul() {
  sed 's/\\/\\\\/g;s/\x0/\\0/g'
}

unquote_nul() {
  echo -en "$1"
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
  [[ -z $x || $x == 0 ]] && printf false || {
    [[ $x == 1 ]] && printf true || issue "Cannot convert '$x' to a Nix boolean."
  }
}

# Based on `escapeNixString`:
# https://github.com/NixOS/nixpkgs/blob/d4224f05074b6b8b44fd9bd68e12d4f55341b872/lib/strings.nix#L316
nix_str() {
  str=$(jq --null-input --arg str "$*" '$str')
  printf '%s' "${str//\$/\\\$}"
}

nix_typed() {
  local type=$1 raw=$2
  case $type in
    file) value="($raw)";;
    attr) value="pkgs: with pkgs; let inherit (pkgs) builtins; in ($raw); name = $(nix_str "$raw")";;
    expr) value="pkgs: with pkgs; let inherit (pkgs) builtins; in ($raw)";;
     str) value=$(nix_str "$raw");;
       *) die_help "Unsupported expression type '$type'.";;
  esac
  printf '{ type = "%s"; value = %s; }' "$type" "$value"
}

capture_err_verbose_out() {
  if (( verbose )); then
    # https://unix.stackexchange.com/questions/430161/redirect-stderr-and-stdout-to-different-variables-without-temporary-files/430182#430182
    {
      "$@" >&2 2> /dev/fd/3
      local ret=$?
      err=$(cat <&3)
      return $ret
    } 3<<EOF
EOF
  else
    err=$("$@" 2>&1)
  fi
}

nix_eval_args=()
nix_eval() {
  local output_type=$1; shift
  local nix=$1; shift
  nix eval "$output_type" "(
    with $args_nix;
    with import $lib/pkgs.nix nixpkgsPath;
    $nix
  )" "${nix_eval_args[@]}" "$@"
}

nix_call() {
  local name=$1; shift
  (( verbose )) && print_nix_eval "$name" "$args_nix"
  nix_eval "$@"
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
  man --pager=cat nix-prefetch | col --no-backspaces --spaces | awk '
    $1 == "SYNOPSIS" { print "Usage:"; between=1; next }
    between == 1 { match($0, /^ */); between=2 }
    $1 ~ /^[A-Z]+$/ { between=0 }
    between && ! /^[[:space:]]*$/ { print "  " substr($0, RLENGTH + 1) }
  '
}

show_help() {
  man nix-prefetch
}

show_version() {
  echo "$version"
}

handle_common() {
  [[ -n $file ]] || file='<nixpkgs>'
  (( silent )) && exec 2> /dev/null
  (( debug )) && nix_eval_args+=( --show-trace )
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
      handle_common
      (( verbose )) && print_bash_vars 'file deep silent verbose debug'
      args_nix="{
        nixpkgsPath = ($file);
        deep = $(nix_bool "$deep");
      }"
      nix_call 'listFetchers' --raw "(
        with prelude;
        lines (import $lib/list-fetchers.nix { inherit prelude pkgs deep; })
      )"
      exit
    ;;
  esac
done

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
    --fetchurl|--print-urls|--print-path|--print-urls|--force|--no-hash|--autocomplete|--help)
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

handle_common

if [[ -v fetcher ]]; then
  [[ $fetcher == */* && -e $fetcher || $fetcher == '<'* ]] && type='file' || type='attr'
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
while (( $# >= 1 )) && [[ $1 == --* ]]; do
  arg=$1; arg=${arg#--*}; shift

  case $arg in
    autocomplete|help) declare "${arg}=1";;
    *) false;;
  esac && continue

  if (( $# == 0 )) || [[ ! $1 =~ ^(-f|--file|-A|--attr|-E|--expr)$ && $1 == --* ]]; then
    type='expr'
    case $arg in
      no-*) value='false'; arg=${arg#no-};;
         *) value='true';;
    esac
  else
    (( $# >= 1 )) || die_option_param
    type='str'
    value=$1; shift
    case $value in
      -f|--file) type='file';;
      -A|--attr) type='attr';;
      -E|--expr) type='expr';;
      *) false;;
    esac && {
      (( $# >= 1 )) || die_option_param
      value=$1; shift
    }
  fi

  fetcher_args[$arg]=$(nix_typed "$type" "$value")
done

if [[ -n $input_type ]]; then
  [[ $input_type == raw ]] && quoted_input=$(quote_nul < /dev/stdin) || input=$(< /dev/stdin)
  if [[ $input_type == nix ]]; then
    input=$(nix-instantiate --eval --strict --expr '{ input }: builtins.toJSON input' --arg input "$input" "${nix_eval_args[@]}") || exit
    input=$(jq 'fromjson' <<< "$input") || exit
  fi
  if [[ $input_type =~ ^(json|nix)$ ]]; then
    quoted_input=$(jq --join-output 'to_entries | .[] | .key + "=" + .value + "\u0000"' <<< "$input" | quote_nul) || exit
  fi
  while IFS= read -r -d '' line; do
    [[ $line == *'='* ]] || die "Expected a name value pair seperated by an equal sign, yet got input line '$line'."
    IFS='=' read -r name value <<< "$line"
    fetcher_args[$name]=$(nix_typed 'str' "$value")
  done < <(unquote_nul "$quoted_input")
fi

if (( verbose )); then
  printf '%s\n' "$(print_bash_vars 'file expr index fetcher fetchurl hash hash_algo input_type output_type print_path print_urls no_hash force silent quiet verbose debug autocomplete help' 2>&1)" >&2
  for name in "${!fetcher_args[@]}"; do
    value=${fetcher_args[$name]}
    print_assign "fetcher_args[$name]" "$value"
  done
  echo >&2
fi

(( $# == 0 )) || die_help "Finished parsing the command line arguments, yet still found the following arguments remaining:$( for arg in "$@"; do printf ' %s' "$(quote "$arg")"; done )."
[[ -v expr_type ]] || die_help "At least a file, attribute, expression, or URL should have been given."

(( print_path )) && [[ $output_type != raw ]] && die "The print path option only works with the default raw output."
(( print_urls )) && [[ $output_type != raw ]] && die "The print URLs option only works with the default raw output."

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
  fetchURL = $(nix_bool "$fetchurl");
}"

if ! overlays=$(sed -nE 's/.*nixpkgs-overlays=([^:]*)(:|$).*/\1/p' <<< "$NIX_PATH"); then
  if   [[ -e $HOME/.config/nixpkgs/overlays.nix ]]; then
    overlays=$HOME/.config/nixpkgs/overlays.nix
  elif [[ -e $HOME/.config/nixpkgs/overlays ]]; then
    overlays=$HOME/.config/nixpkgs/overlays
  fi
fi

[[ -e $XDG_RUNTIME_DIR/nix-prefetch ]] && rm -r $XDG_RUNTIME_DIR/nix-prefetch
mkdir "$XDG_RUNTIME_DIR/nix-prefetch"

printf '%s\n' "$( [[ -v fetcher ]] && echo "$fetcher" || echo null )" > $XDG_RUNTIME_DIR/nix-prefetch/fetcher.nix

nixpkgs_overlays=$XDG_RUNTIME_DIR/nix-prefetch/overlays
if [[ -n $overlays ]]; then
  if [[ -f $overlays ]]; then
    nixpkgs_overlays+=.nix
    { cat "$overlays"; echo ' ++ [ ('; cat "$lib/fetcher-overlay.nix"; echo ') ]'; } > "$nixpkgs_overlays"
  else
    mkdir "$nixpkgs_overlays"
    ln -s "$overlays/"* "$nixpkgs_overlays/"
    ln -s "$lib/fetcher-overlay.nix" "$nixpkgs_overlays/nix-prefetch.nix"
  fi
else
  mkdir "$nixpkgs_overlays"
  ln -s "$lib/fetcher-overlay.nix" "$nixpkgs_overlays/nix-prefetch.nix"
fi
nix_eval_args+=( -I "nixpkgs-overlays=$nixpkgs_overlays" )

fetcher_autocomplete() {
  out=$(nix_call 'fetcherAutocomplete' --raw "(
    with prelude;
    with import $lib/fetcher.nix { inherit prelude pkgs expr index fetcher; };
    lines' (attrNames (functionArgs fetcher))
  )") || exit
  [[ -n $out ]] && printf '%s\n' "$out" || exit 1
}

fetcher_help() {
  usage=$(man --pager=cat nix-prefetch | col --no-backspaces --spaces | awk '
    $1 == "SYNOPSIS" { between=1; next }
    between == 1 { match($0, /^ */); between=2; next }
    $1 == "nix-prefetch" { between=0 }
    between { print "  " substr($0, RLENGTH + 1) }
  ')
  nix_call 'fetcherHelp' --raw "(
    with import $lib/fetcher.nix { inherit prelude pkgs expr index fetcher; };
    import $lib/fetcher-help.nix { inherit prelude pkgs pkg fetcher; usage = $(nix_str "$usage"); }
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
    (( debug )) && [[ -n $out ]] && printf '%s\n' "$out" >&2
    [[ -n $err ]] && sed '/./,$!d' <<< "$err" >&2
    exit 1
  fi
}

hash_builtin() {
  capture_err_verbose_out nix_eval --raw "(
    with import $lib/fetcher.nix { inherit prelude pkgs expr index fetcher; };
    with import $lib/prefetcher.nix { inherit prelude pkgs pkg fetcher fetcherArgs hashAlgo hash fetchURL; };
    prefetcher prefetcher.args
  )" && issue_no_hash_mismatch || hash_from_err
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
  capture_err_verbose_out nix-store --quiet --realize "$wrong_drv_path" && issue_no_hash_mismatch || hash_from_err
}

prefetch() {
  out=$(nix_call 'prefetch' --json "(
    with import $lib/fetcher.nix { inherit prelude pkgs expr index fetcher; };
    with import $lib/prefetcher.nix { inherit prelude pkgs pkg fetcher fetcherArgs hashAlgo hash fetchURL; };
    json
  )" --option allow-unsafe-native-code-during-evaluation true) || exit

  if ! vars=$(jq --raw-output '.bash_vars | to_entries | .[] | .key + "=" + .value' <<< "$out"); then
    [[ -n $out ]] && echo "$out" >&2
    issue "The Nix code was unable to produce valid JSON."
  fi
  while IFS= read -r var; do declare "$var"; done <<< "$vars"
  (( verbose )) && print_bash_vars "$(jq --raw-output '.bash_vars | keys | join(" ")' <<< "$out")"

  [[ $fetcher != requireFile ]] || die_require_file

  log=$(jq --raw-output '.log' <<< "$out")
  (( ! quiet )) && [[ -n $log ]] && echo "$log" >&2 && echo >&2

  (( ! hash_support && ! no_hash )) && die "The fetcher '$fetcher' does not support hashes, use the `--no-hash` option to ignore hashes."

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
  with import $lib/pkgs.nix nixpkgsPath;
  with import $lib/fetcher.nix { inherit prelude pkgs expr index fetcher; };
  with import $lib/prefetcher.nix { inherit prelude pkgs pkg fetcher fetcherArgs hashAlgo hash fetchURL; };
  { inherit pkgs fetcher prefetcher; }
)";;
    nix) nix-instantiate --eval --strict --expr '{ json }: builtins.fromJSON json' --argstr json "$json";;
    json) echo "$json";;
    shell) jq --join-output 'to_entries | .[] | .key + "=" + .value + "\u0000"' <<< "$json";;
    raw) echo "$actual_hash";;
  esac

  if (( print_path )); then
    if [[ $fetcher == builtins.* ]]; then
      output=$(nix_eval --raw "(
        with import $lib/fetcher.nix { inherit prelude pkgs expr index fetcher; };
        with import $lib/prefetcher.nix { inherit prelude pkgs pkg fetcher fetcherArgs hashAlgo hash fetchURL; };
        prefetcher (prefetcher.args $( (( hash_support )) && echo "// { ${hash_algo} = \"${actual_hash}\"; }" ))
      )") || exit
    fi
    echo "$output"
  fi

  (( print_urls )) && jq --raw-output '.urls[]' <<< "$out"

  return 0
}

if (( help )); then
  fetcher_help
elif (( autocomplete )); then
  fetcher_autocomplete
else
  prefetch
fi
