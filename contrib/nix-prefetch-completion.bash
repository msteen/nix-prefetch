_nix_prefetch_reply() {
  [[ -n $1 ]] && mapfile -t -O "${#COMPREPLY}" COMPREPLY <<< "$1"
}

_nix_prefetch_attrs() {
  # Based on `escapeNixString`:
  # https://github.com/NixOS/nixpkgs/blob/d4224f05074b6b8b44fd9bd68e12d4f55341b872/lib/strings.nix#L316
  str=$(jq --null-input --arg str "$1" '$str')
  str="${str//\$/\\\$}"
  _nix_prefetch_reply "$(nix eval --raw '(
    let pkgs = import <nixpkgs> { }; in with pkgs.lib;
    concatMapStrings (s: s + "\n") (filter (hasPrefix '"$str"') (attrNames pkgs))
  )' 2> /dev/null)"
}

_nix_prefetch() {
  local params=' -f --file -A --attr -E --expr -i --index -F --fetcher -t --type --hash-algo -h --hash --input --output '
  local flags=' --fetch-url --print-path --no-hash --force --deep -l --list -q --quiet -v --verbose -vv --debug --help --version '

  COMPREPLY=()
  local prev_word=${COMP_WORDS[COMP_CWORD - 1]}
  local curr_word=${COMP_WORDS[COMP_CWORD]}

  if (( COMP_CWORD > 1 )) && [[ $prev_word == -* && $params == *" $prev_word "* ]]; then
    case $prev_word in
      -f|--file)
        _nix_prefetch_reply "$(compgen -f -- "$curr_word")"
        ;;
      -A|--attr)
        _nix_prefetch_attrs "$curr_word"
        ;;
      -E|--expr|-F|--fetcher)
        _nix_prefetch_reply "$(compgen -f -- "$curr_word")"
        _nix_prefetch_attrs "$curr_word"
        ;;
      -t|--type|--hash-algo)
        local values='md5 sha1 sha256 sha512'
        _nix_prefetch_reply "$(compgen -W "$values" -- "$curr_word")"
        ;;
      --input)
        local values='nix json shell'
        _nix_prefetch_reply "$(compgen -W "$values" -- "$curr_word")"
        ;;
      --output)
        local values='expr nix json shell raw'
        _nix_prefetch_reply "$(compgen -W "$values" -- "$curr_word")"
        ;;
    esac
    return 0
  fi

  local given_args
  if [[ -n $_nix_prefetch_all_args ]]; then
    for word in "${COMP_WORDS[@]}"; do
      [[ $_nix_prefetch_all_args == *" $word "* ]] && given_args+=" $word"
    done
    [[ -n $given_args ]] && given_args+=' '
  fi

  local all_args
  if [[ -z $_nix_prefetch_all_args || $given_args != $_nix_prefetch_given_args ]] &&
    all_args=$(nix-prefetch --silent "${COMP_WORDS[@]:1:${#COMP_WORDS[@]} - 2}" --autocomplete)
  then
    all_args=$(sed 's/^/--/' <<< "$all_args")
    _nix_prefetch_given_args=$given_args
    _nix_prefetch_all_args=" $(echo $all_args) "
  fi

  _nix_prefetch_reply "$(compgen -f -- "$curr_word")"
  _nix_prefetch_attrs "$curr_word"
  _nix_prefetch_reply "$(compgen -W "$_nix_prefetch_all_args $params $flags" -- "$curr_word")"
}

complete -F _nix_prefetch nix-prefetch
