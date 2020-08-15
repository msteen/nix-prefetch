#!/usr/bin/env bash
# shellcheck disable=SC1003 disable=SC2015 disable=SC2016 disable=SC2030 disable=SC2031

# Tested succesfully with:
# set -euxo pipefail

shopt -s extglob

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

exit_with_error() {
  local ret=$1; shift
  (( ! silent )) && printf 'error: %s\n' "$*" >&2
  (( ret )) && exit_script "$ret" || exit_script 1
}

die() {
  exit_with_error $? "$@"
}

# Allow the source to be used directly when developing.
# To prevent `--subst-var-by lib` from replacing the string literal in the equality check,
# the string literal for it has been broken up.
if [[ $lib == '@''lib''@' ]]; then
  case $PWD in
    */nix-prefetch/lib) lib=$PWD;;
    */nix-prefetch/src) lib=$(realpath "$PWD/../lib");;
    */nix-prefetch) lib=$PWD/lib;;
    *) die "The script backing nix-prefetch called from an unsupported location: ${PWD}."
  esac
fi

die_usage() {
  local ret=$?
  (( ! quiet )) && { show_usage; printf '\n'; } >&2
  exit_with_error $ret "$@"
}

issue() {
  (( ! silent )) && printf '%s\nPlease report an issue at: %s\n' "$*" 'https://github.com/msteen/nix-prefetch/issues' >&2
  exit_script 1
}

quote() {
  [[ $1 =~ ^[a-zA-Z0-9_\.-]+$ ]] <<< "$1" && printf '%s' "$1" || printf '%s' "'${1//'/\\'}'"
}

quote_args() {
  for arg in "$@"; do
    printf '%s ' "$(quote "$arg")"
  done
}

# https://stackoverflow.com/questions/6570531/assign-string-containing-null-character-0-to-a-variable-in-bash
quote_nul() {
  sed 's/\\/\\\\/g;s/\x0/\\x00/g'
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
  # shellcheck disable=SC2048
  for var in $*; do
    [[ -v $var ]] && print_assign "$var" "${!var}"
  done
}

print_bash_vars() {
  (( debug )) && printf 'The following Bash variables have been set:\n%s\n\n' "$(print_vars "$1" 2>&1)" >&2 || true
}

nix_bool() {
  local x=$*
  [[ -z $x || $x == 0 || $x == 1 ]] || issue "Cannot convert '${x}' to a Nix boolean."
  (( x )) && echo true || echo false
}

# Based on `escapeNixString`:
# https://github.com/NixOS/nixpkgs/blob/d4224f05074b6b8b44fd9bd68e12d4f55341b872/lib/strings.nix#L316
nix_str() {
  str=$(jq --null-input --arg str "$*" '$str')
  printf '%s' "${str//\$/\\\$}"
}

printf -v lib_nix '%s + toString ' "$(nix_str "$lib")"

nix_expr_scope='pkgs: with pkgs.lib; with pkgs; let inherit (pkgs) builtins; inherit (builtins) fetchTarball import; in'
nix_typed() {
  local type=$1 raw=$2
  case $type in
    file) value="(${raw})";;
    attr) value="$nix_expr_scope (${raw}); name = $(nix_str "$raw")";;
    expr) value="$nix_expr_scope (${raw})";;
     str) value=$(nix_str "$raw");;
       *) die_usage "Unsupported expression type '${type}'.";;
  esac
  printf '{ type = "%s"; value = %s; }' "$type" "$value"
}

capture_err() {
  if (( verbose )); then
    # https://unix.stackexchange.com/questions/430161/redirect-stderr-and-stdout-to-different-variables-without-temporary-files/430182#430182
    {
      "$@" 2> >(awk '
        /instead of the expected hash/ || /hash mismatch/ { hash_mismatch=1 }
        { if (hash_mismatch) { print }
          else if (printed_stderr || $0 != "") { print > "/dev/stderr"; printed_stderr=1 } }
        END { if (printed_stderr) { print "" > "/dev/stderr" } }
      ' > /dev/fd/3)
      local ret=$?
      err=$(cat <&3)
      return $ret
    } 3<<EOF
EOF
  else
    err=$("$@" 2>&1)
  fi
}

# The version of Nix with Flakes support requires the expression to be passed through flags,
# which are not present in previous versions, so to be backwards compatible, we conditionally pass them.
# The `nix-command` feature is not enabled by default, so enable it explicitly just in case.
nix flake --help &>/dev/null && nix_eval_expr_args=( --impure --expr --experimental-features nix-command ) || nix_eval_expr_args=()
nix_eval_args=()
nix_eval() {
  local output_type=$1; shift
  local nix=$1; shift
  nix eval "${nix_eval_expr_args[@]}" "$output_type" "(
    let
      args = ${args_nix};
      prelude = import ($lib_nix/prelude.nix) { inherit (args) fetcher forceHTTPS; };
      pkgs = import ($lib_nix/pkgs.nix) { inherit prelude; inherit (args) nixpkgsPath; };
    in
    with prelude;
    with args;
    ${nix}
  )" "${nix_eval_args[@]}" "$@"
}

nix_eval_prefetcher() {
  local output_type=$1; shift
  local nix=$1; shift
  nix_eval "$output_type" "(
    with import ($lib_nix/fetcher.nix) { inherit prelude pkgs expr exprArgs index fetcher; };
    with import ($lib_nix/prefetcher.nix) { inherit prelude pkgs pkg fetcher fetcherArgs hashAlgo hash fetchURL forceHTTPS; };
    ${nix}
  )" "$@"
}

nix_call() {
  local name=$1; shift
  (( debug )) && call=$( { head -1; unindent "$(cat)"; } <<< "$name $args_nix" | sed 's/^/> /' ) &&
    printf 'The following Nix function call will be evaluated:\n%s\n\n' "$call" >&2 || true
}

## ##
## Command line arguments
## ##

die_extra_param() {
  die_usage "An unexpected extra parameter '${1}' has been given."
}

die_option_param() {
  die_usage "The option '${arg}' needs a parameter."
}

die_option_name_value() {
  die_usage "The option '${arg}' needs a name and value."
}

show_usage() {
  { man --pager=cat nix-prefetch | col --no-backspaces --spaces || true; } | awk '
    $1 == "SYNOPSIS" { print "Usage:"; between=1; next }
    between && $1 ~ /^[A-Z]+$/ { exit }
    between == 1 { match($0, /^ */); between=2 }
    between && ! /^[[:space:]]*$/ { print "  " substr($0, RLENGTH + 1) }
  '
}

handle_common() {
  [[ -v file && -n $file ]] || file='<nixpkgs>'
  (( silent )) && exec 2> /dev/null
  (( debug )) && nix_eval_args+=( --show-trace )

  if ! overlays=$(nix-instantiate --find-file nixpkgs-overlays "${nix_eval_args[@]}" 2> /dev/null); then
    if   [[ -e $HOME/.config/nixpkgs/overlays.nix ]]; then
      overlays=$HOME/.config/nixpkgs/overlays.nix
    elif [[ -e $HOME/.config/nixpkgs/overlays ]]; then
      overlays=$HOME/.config/nixpkgs/overlays
    fi
  fi

  if [[ -z $XDG_RUNTIME_DIR ]]; then
    XDG_RUNTIME_DIR=/run/user/$(id -u)
    [[ -d $XDG_RUNTIME_DIR ]] || die "Could not determine the runtime directory (i.e. XDG_RUNTIME_DIR)."
    export XDG_RUNTIME_DIR
  fi

  mkdir -p "$XDG_RUNTIME_DIR/nix-prefetch"
  export TMPDIR=$(mktemp -d -p "$XDG_RUNTIME_DIR/nix-prefetch")
  remove_TMPDIR() {
    rm -r "$TMPDIR"
  }
  trap remove_TMPDIR EXIT

  nixpkgs_overlays=$TMPDIR/overlays
  if [[ -f $overlays ]]; then
    nixpkgs_overlays+=.nix
    printf 'import (%s) ++ [ (import (%s)) ]\n' "$overlays" "$lib_nix/overlay.nix" > "$nixpkgs_overlays"
  else
    mkdir "$nixpkgs_overlays"
    [[ -n $overlays ]] && ln -s "$overlays/"* "$nixpkgs_overlays/"
    ln -s "$lib/overlay.nix" "$nixpkgs_overlays/~~~nix-prefetch.nix" # `readDir` uses lexical order, and '~' comes last.
  fi
  nix_eval_args+=( -I "nixpkgs-overlays=${nixpkgs_overlays}" )
}

# Each command should be handled differently and to prevent issues like determinig their priorities,
# we do not allow them to be mixed, so e.g. calling adding --version while also having other arguments,
# will just result in the help message being shown with an error code.
(( $# == 1 )) &&
case $1 in
  --help)
    man nix-prefetch
    exit
    ;;
  --version)
    printf '%s\n' "$version"
    exit
    ;;
esac

silent=0; quiet=0; verbose=0; debug=0

# We need to be able to differentiate the remaining commands,
# because they will have different arguments available to them.
for arg in "$@"; do
  case $arg in
    -l|--list)
      deep=0
      while (( $# >= 1 )); do
        arg=$1; shift
        case $arg in
          -f|--file)
            (( $# >= 1 )) || die_option_param
            file=$1
            ;;
          --no-deep) deep=0;;
          --deep) deep=1;;
          -s|--silent)  silent=1; verbose=0;;
          -v|--verbose) silent=0; verbose=1;;
          -vv|--debug)  silent=0; verbose=1; debug=1;;
          *) [[ $arg =~ ^(-l|--list)$ ]] || die_extra_param "$arg";;
        esac
      done
      handle_common
      print_bash_vars 'file deep silent verbose debug'
      args_nix="{
        nixpkgsPath = (${file});
        deep = $(nix_bool "$deep");
      }"
      nix_call 'listFetchers'
      nix_eval --raw "(
        with prelude;
        lines (listFetchers pkgs deep)
      )"
      exit
    ;;
  esac
done

expr_type=; input_type=; output_type=raw; eval=
fetchurl=0; force_https=1; print_urls=0; print_path=0; compute_hash=1; check_store=0; autocomplete=0; help=0
declare -A expr_args
declare -A fetcher_args
param_count=0
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
    --eval) param='eval';;
    --?(no-)@(fetchurl|force-https|print-urls|print-path|compute-hash|check-store|autocomplete|help))
      name=${arg#--}
      [[ $name == no-* ]] && name=${name#no-} && value=0 || value=1
      name=${name//-/_}
      declare "${name}=${value}"
      ;;
    --arg|--argstr)
      (( $# >= 2 )) || die_option_name_value
      name=$1; shift
      value=$1; shift
      [[ $arg == --argstr ]] && value=$(nix_str "$value")
      expr_args[$name]=$value
      ;;
    -I)
      (( $# >= 1 )) || die_option_param
      nix_eval_args+=( -I "$1" ); shift
      ;;
    --option)
      (( $# >= 2 )) || die_option_name_value
      nix_eval_args+=( --option "$1" "$2" ); shift; shift
      ;;
    -s|--silent)  silent=1; quiet=1; verbose=0; debug=0;;
    -q|--quiet)   silent=0; quiet=1; verbose=0; debug=0;;
    -v|--verbose) silent=0; quiet=0; verbose=1;;
    -vv|--debug)  silent=0; quiet=0; verbose=1; debug=1;;
    *)
      if [[ $arg == --* ]]; then
        disambiguate=0
        while true; do
          if [[ $arg == -- ]]; then
            disambiguate=1
            (( $# >= 1 )) && [[ $1 == --* ]] && arg=$1 && shift && continue || break
          fi

          name=${arg#--*}

          if (( $# == 0 )) || [[ ! $1 =~ ^(-f|--file|-A|--attr|-E|--expr)$ && $1 == -* ]]; then
            type='expr'
            case $name in
              no-*) value='false'; name=${name#no-};;
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

          fetcher_args[$name]=$(nix_typed "$type" "$value")

          (( disambiguate )) && (( $# >= 1 )) && [[ $1 == --* ]] && arg=$1 && shift || break
        done
        (( disambiguate )) && break || continue
      fi
      if (( param_count == 0 )); then
        expr=$arg
        if [[ $arg =~ ^[a-zA-Z]+:// ]]; then
          expr_type='url'
        elif [[ $arg == */* && -e $arg || $arg == '<'* ]]; then
          expr_type='file'
        elif [[ $arg =~ ^[a-zA-Z0-9_\-]+(\.[a-zA-Z0-9_\-]+)*$ ]]; then
          expr_type='attr'
        else
          expr_type='expr'
        fi
      elif (( param_count == 1 )); then
        hash=$arg
      else
        die_extra_param "$arg"
      fi
      (( param_count++ )) || true
      ;;
  esac
  if [[ -n $param ]]; then
    (( $# >= 1 )) || die_option_param
    declare "${param}=${1}"; shift
  fi
done

handle_common

[[ $input_type =~ ^(|nix|json|shell)$ ]] || die "Unsupported input type '${input_type}'."
[[ $output_type =~ ^(nix|json|shell|raw)$ ]] || die "Unsupported output type '${output_type}'."

if [[ -v fetcher ]]; then
  [[ $fetcher == */* && -e $fetcher || $fetcher == '<'* ]] && type='file' || type='attr'
  fetcher=$(nix_typed "$type" "$fetcher")
fi

if [[ $input_type == shell ]]; then
  while IFS= read -r -d '' line; do
    [[ $line == *'='* ]] || die "Expected a name-value pair seperated by an equal sign, yet got input line '${line}'."
    IFS='=' read -r name value <<< "$line"
    fetcher_args[$name]=$(nix_typed 'str' "$value")
  done < /dev/stdin
fi

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

# The NIX_PATH lookup is done regardless of whether it is truly necessary,
# because we e.g. do not want it to fail on not being able to resolve 'nixpkgs/lib',
# while the missing 'nixpkgs' would be the culprit.
if [[ $file == '<'*'>' ]]; then
  value=$(nix-instantiate --find-file "${file:1:-1}" "${nix_eval_args[@]}") || exit
  if [[ $file != '<nixpkgs>' ]]; then
    file=$value
    nix_eval_args+=( -I "nixpkgs=$file" )
  fi
fi

if (( debug )); then
  printf '%s\n' "$(print_bash_vars '
    file expr index fetcher fetchurl force_https hash hash_algo input_type output_type print_path print_urls
    compute_hash check_store silent quiet verbose debug eval autocomplete help
  ' 2>&1)" >&2
  for name in "${!expr_args[@]}"; do
    value=${expr_args[$name]}
    print_assign "expr_args[$name]" "$value"
  done
  for name in "${!fetcher_args[@]}"; do
    value=${fetcher_args[$name]}
    print_assign "fetcher_args[$name]" "$value"
  done
  echo >&2
fi

(( $# == 0 )) || die_usage "Finished parsing the command line arguments, yet still found the following arguments remaining: $(quote_args "$@")."
[[ -n $expr_type ]] || die_usage "At least a file, attribute, expression, or URL should have been given."

## ##
## Main commands
## ##

die_no_raw_output() {
  die "The $1 option only works with the default raw output."
}

if [[ $output_type != raw ]]; then
  (( print_path )) && die_no_raw_output '--print-path'
  (( print_urls )) && die_no_raw_output '--print-urls'
fi

if (( ${#expr_args[@]} > 0 )); then
  expr_args_nix="$nix_expr_scope { "
  for name in "${!expr_args[@]}"; do
    value=${expr_args[$name]}
    expr_args_nix+="${name} = (${value}); "
  done
  expr_args_nix+='}'
else
  expr_args_nix=null
fi

expr=$(nix_typed "$expr_type" "$expr")

case $input_type in
  json) fetcher_args_nix="builtins.fromJSON $(nix_str "$(< /dev/stdin)")";;
   nix) fetcher_args_nix="( $(< /dev/stdin) )";;
     *) fetcher_args_nix=; false;;
esac && printf -v fetcher_args_nix 'prelude.mapAttrs (_: value: %s) (%s) // ' "$(nix_typed 'expr' 'value')" "$fetcher_args_nix"

fetcher_args_nix+='{'
for name in "${!fetcher_args[@]}"; do
  value=${fetcher_args[$name]}
  fetcher_args_nix+=$'\n    '"${name} = ${value};"
done
[[ $fetcher_args_nix != '{' ]] && fetcher_args_nix+=$'\n  '
fetcher_args_nix+='}'

args_nix="{
  nixpkgsPath = (${file});
  expr = ${expr};
  exprArgs = ${expr_args_nix};
  index = $( [[ -v index ]] && printf '%s\n' "$index" || echo null );
  fetcher = $( [[ -v fetcher ]] && printf '%s\n' "$fetcher" || echo null );
  fetcherArgs = ${fetcher_args_nix};
  hashAlgo = $( [[ -v hash_algo ]] && nix_str "$hash_algo" || echo null );
  hash = $( [[ -v hash ]] && nix_str "$hash" || echo null );
  fetchURL = $(nix_bool "$fetchurl");
  forceHTTPS = $(nix_bool "$force_https");
}"

printf '%s\n' "{
  fetcher = $( [[ -v fetcher ]] && printf '%s\n' "$fetcher" || echo null );
  forceHTTPS = $(nix_bool "$force_https");
}" > "$TMPDIR/prelude-args.nix"

fetcher_autocomplete() {
  nix_call 'fetcherAutocomplete'
  out=$(nix_eval_prefetcher --raw 'concatMapStrings (arg: "--${arg}\n") (attrNames (functionArgs fetcher))') || exit
  [[ -n $out ]] && printf '%s\n' "$out" || exit 1
}

fetcher_help() {
  usage=$( { man --pager=cat nix-prefetch | col --no-backspaces --spaces || true; } | awk '
    $1 == "SYNOPSIS" { between=1; next }
    between == 1 { match($0, /^ */); between=2; next }
    between && $1 == "nix-prefetch" { exit }
    between { print "  " substr($0, RLENGTH + 1) }
  ' )
  nix_call 'fetcherHelp'
  nix_eval_prefetcher --raw "import ($lib_nix/fetcher-help.nix) { inherit prelude pkgs pkg fetcher; usage = $(nix_str "$usage"); }"
}

die_require_file() {
  read -r url name < <(jq --raw-output '.fetcher_args | [.url, .name] | @tsv' <<< "$out")
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
  # The hash mismatch error message has changed in version 2.2 of Nix, swapping the order of the reported hashes.
  # https://github.com/NixOS/nix/commit/5e6fa9092fb5be722f3568c687524416bc746423
  local head_or_tail=$([[ $err == *'instead of the expected hash'* ]] && echo head || echo tail)
  if ! actual_hash=$(grep --extended-regexp --only-matching "[a-z0-9]{${actual_hash_size}}|${hash_algo}-[A-Za-z0-9/+=]+" <<< "$err" > >($head_or_tail -1)); then
    (( debug )) && [[ -n $out ]] && printf '%s\n' "$out" >&2
    [[ -n $err ]] && sed '/./,$!d' <<< "$err" >&2
    exit 1
  fi
}

# Check whether the output path of the fetcher produced derivation already exists in the Nix store.
compute_hash_store() {
  # This check would have been easy if `nix-store --query --deriver` would have returned the actual derivation
  # responsible for building it, but it does not: https://github.com/NixOS/nix/issues/2631
  # So instead the following approximation will have to do:
  local drvs outputs

  # Are there any derivations in the Nix store that refer to the fetcher produced derivation?
  drvs=$(nix-store --query --referrers "$drv_path")

  # What output paths do these derivations produce?
  # shellcheck disable=SC2086
  outputs=$(nix-store --query --outputs $drvs)

  # We have to check for non-emptiness, otherwise the while loop will process the empty string as a path.
  # What of these output paths actually exist in the Nix store?
  [[ -n $outputs ]] && outputs=$( while IFS= read -r p; do [[ -e $p ]] && printf '%s\n' "$p"; done <<< "$outputs" )

  # Checking for roots is the slowest command of all, even without arguments,
  # so we first check if there were any output paths that exist.
  # Are there any roots to the output paths, i.e. are they considered installed?
  # shellcheck disable=SC2086
  [[ -n $outputs ]] && roots=$(nix-store --query --roots $outputs)

  # Again first check for non-emptiness, otherwise the check would succeed for the empty string,
  # as the basename of it is still the empty string, which is not equal to 'result'.
  # We ignore 'result' roots, because they are generally the produced by calling `nix-build`,
  # so it could happen that a package with an updated version but outdated hash would be build with it,
  # producing false positives for the checks being done so far.
  [[ -n $roots ]] && while IFS= read -r root; do
    if [[ $(basename "$root") != result ]]; then
      # There is something installed that used the same derivation as produced by the fetcher,
      # so we can be confident that the hash passed to the fetcher was already valid.
      actual_hash=$expected_hash
      return 0
    fi
  done <<< "$roots"

  # Failed to find any.
  return 1
}

compute_hash_nix_prefetch_url() {
  local args=()
  (( print_path )) && args+=( --print-path )
  [[ $fetcher =~ ^(builtins.fetchTarball|fetchTarball)$ ]] && args+=( --unpack )
  read -r url name < <(jq --raw-output '.fetcher_args | [.url, .name // empty] | @tsv' <<< "$out")
  [[ -n $name ]] && args+=( --name "$name" )
  args+=( "$url" )
  (( check_hash )) && args+=( "$expected_hash" )
  {
    local out ret
    out=$(nix-prefetch-url --type "$hash_algo" "${args[@]}" 2> >(awk '
      /path is '\''\/nix\/store\/[^'\'']+'\''/ { next }
      { print }
    ' > /dev/fd/3))
    ret=$?
    cat <&3 >&2
    (( ! ret )) || exit $ret
    IFS=$'\n' read -r -d '' actual_hash output <<< "$out"
  } 3<<EOF
EOF
}

compute_hash_builtin() {
  capture_err nix_eval_prefetcher --raw 'prefetcher.drv' && issue_no_hash_mismatch || hash_from_err
}

compute_hash_generic() {
  capture_err nix-store --quiet --realize "$wrong_drv_path" && issue_no_hash_mismatch || hash_from_err
}

prefetch() {
  nix_call 'prefetch'
  out=$(nix_eval_prefetcher --json 'json' --option allow-unsafe-native-code-during-evaluation true) || exit

  if ! vars=$(jq --raw-output '.bash_vars | to_entries | .[] | .key + "=" + .value' <<< "$out"); then
    [[ -n $out ]] && printf '%s\n' "$out" >&2
    issue "The Nix code was unable to produce valid JSON."
  fi
  fetcher=; hash_algo=; expected_hash=; actual_hash_size=; check_hash=; hash_support=; drv_path=; wrong_drv_path=; output=
  while IFS= read -r var; do declare "$var"; done <<< "$vars"
  print_bash_vars "$(jq --raw-output '.bash_vars | keys | join(" ")' <<< "$out")"

  [[ $fetcher != requireFile ]] || die_require_file
  (( ! hash_support && compute_hash )) && die "The fetcher '${fetcher}' does not support hashes, use the --no-compute-hash option to not let the fetcher compute it."

  [[ $fetcher =~ ^(fetchurlBoot|builtins.fetchurl|builtins.fetchTarball|fetchTarball)$ ]] && use_nix_prefetch_url=1

  log=$(jq --raw-output '.log' <<< "$out")
  (( ! quiet )) && [[ -n $log ]] && printf '%s\n\n' "$log" >&2

  use_nix_prefetch_url=0
  if (( compute_hash )); then
    (( check_store )) && compute_hash_store || {
      if (( verbose )); then
        local urls
        urls=$(jq --raw-output '.urls[]' <<< "$out") || exit
        [[ -n $urls ]] && printf 'The following URLs will be fetched as part of the source:\n%s\n\n' "$urls" >&2
      fi
      if (( use_nix_prefetch_url )); then
        compute_hash_nix_prefetch_url
      elif [[ $fetcher == builtins.* ]]; then
        compute_hash_builtin
      else
        compute_hash_generic
      fi
    }
  else
    actual_hash=$expected_hash
  fi

  if (( check_hash )) && [[ $expected_hash != "$actual_hash" ]]; then
    die "A hash mismatch occurred for the fixed-output derivation output ${output}:
  expected: ${expected_hash}
    actual: ${actual_hash}"
  fi

  if [[ -n $eval ]]; then
    nix_eval_prefetcher --raw "with builtins; with pkgs.lib; ($eval) {
      inherit pkgs fetcher;
      prefetcher = prefetcher // rec {
        args = prefetcher.args // { ${hash_algo} = \"${actual_hash}\"; };
        drv = prefetcher args;
      };
    }" --option allow-unsafe-native-code-during-evaluation true
    exit
  fi

  [[ $output_type == raw ]] || json=$(jq --raw-output '.fetcher_args | .'"$hash_algo"' = "'"$actual_hash"'"' <<< "$out")
  case $output_type in
    nix) nix-instantiate --eval --strict --expr '{ json }: builtins.fromJSON json' --argstr json "$json" | sed 's/^{ /{\n  /;s/; /;\n  /g;s/  }$/}/';;
    json) printf '%s\n' "$json";;
    shell) jq --join-output 'to_entries | .[] | .key + "=" + .value + "\u0000"' <<< "$json";;
    raw) printf '%s\n' "$actual_hash";;
  esac

  if (( print_path )); then
    if [[ $fetcher == builtins.* ]] && (( ! use_nix_prefetch_url )); then
      output=$(nix_eval_prefetcher --raw 'prefetcher.drv') || exit
    fi
    printf '%s\n' "$output"
  fi

  if (( print_urls )); then
    jq --raw-output '.urls[]' <<< "$out" || exit
  fi
}

if (( help )); then
  fetcher_help
elif (( autocomplete )); then
  fetcher_autocomplete
else
  prefetch
fi
