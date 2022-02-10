#compdef nix-prefetch

_nix_prefetch_attrs() {
  # Based on `escapeNixString`:
  # https://github.com/NixOS/nixpkgs/blob/d4224f05074b6b8b44fd9bd68e12d4f55341b872/lib/strings.nix#L316
  str=$(jq --null-input --arg str "$1" '$str')
  str="${str//\$/\\\$}"

  # The `nix eval` has a bug causing autocompletion to act buggy when stderr is not redirected to /dev/null,
  # even though there is no output being written to stderr by `nix shell`.
  local -a attrs
  attrs=( $(nix eval --raw '(
    let pkgs = import <nixpkgs> { }; in
    with pkgs.lib;
    concatMapStrings (s: s + "\n") (filter (hasPrefix '"$str"') (attrNames pkgs))
  )' 2> /dev/null) )
  _describe 'attributes' attrs
}

_nix_prefetch() {
  local params=(
    '-f' '--file' '-A' '--attr' '-E' '--expr' '-i' '--index' '-F' '--fetcher' '--arg' '--argstr' '-I' '--option'
    '-t' '--type' '--hash-algo' '-h' '--hash' '--input' '--output' '--eval'
    '--experimental-features' '--extra-experimental-features'
  )
  local flags=( -s --silent -q --quiet -v --verbose -vv --debug -l --list --version ) flag
  for flag in --fetchurl --force-https --print-urls --print-path --compute-hash --check-store --autocomplete --help --deep; do
    flags+=( "--no-${flag#--}" "$flag" )
  done

  local prev_word=${words[CURRENT - 1]}
  local curr_word=${words[CURRENT]}

  if (( CURRENT > 2 && ${params[(i)$prev_word]} <= ${#params} )); then
    case $prev_word in
      -f|--file)
        _files
        ;;
      -A|--attr)
        _nix_prefetch_attrs "$curr_word"
        ;;
      -E|--expr|-F|--fetcher)
        _files
        _nix_prefetch_attrs "$curr_word"
        ;;
      -I)
        if [[ $curr_word == *'='* ]]; then
          # https://unix.stackexchange.com/questions/445889/use-colon-as-filename-separator-in-zsh-tab-completion
          compset -P 1 '*='
          _files
        fi
        ;;
      -t|--type|--hash-algo)
        local values=( 'md5' 'sha1' 'sha256' 'sha512' )
        _describe 'hash-algos' values
        ;;
      --input)
        local values=( 'nix' 'json' 'shell' )
        _describe 'input-types' values
        ;;
      --output)
        local values=( 'nix' 'json' 'shell' 'raw' )
        _describe 'output-types' values
        ;;
    esac
    return 0
  fi

  (( CURRENT == 2 )) && _nix_prefetch_all_args=() || {
    local given_args all_args
    if (( ${#_nix_prefetch_all_args} > 0 )); then
      for word in "${words[@]}"; do (( ${_nix_prefetch_all_args[(i)$word]} <= ${#_nix_prefetch_all_args} )) && given_args+=" $word"; done
      [[ -n $given_args ]] && given_args+=' '
    fi
    if (( ${#_nix_prefetch_all_args} == 0 )) || [[ $given_args != $_nix_prefetch_given_args ]]; then
      _nix_prefetch_given_args=$given_args
      all_args=$(nix-prefetch --silent "${words[@]:1:${#words} - 2}" --autocomplete) &&
        _nix_prefetch_all_args=( $(echo $all_args) ) || _nix_prefetch_all_args=()
    fi
  }

  _files
  _nix_prefetch_attrs "$curr_word"
  _describe 'fetcher-arguments' _nix_prefetch_all_args
  _describe 'params' params
  _describe 'flags' flags
}

_nix_prefetch "$@"
