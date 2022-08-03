_nix_prefetch_reply() {
  [[ -n $1 ]] && mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY <<< "$1"
}

_nix_prefetch_attrs() {
  # Based on `escapeNixString`:
  # https://github.com/NixOS/nixpkgs/blob/d4224f05074b6b8b44fd9bd68e12d4f55341b872/lib/strings.nix#L316
  str=$(jq --null-input --arg str "$1" '$str')
  str="${str//\$/\\\$}"

  # The `nix eval` has a bug causing autocompletion to act buggy when stderr is not redirected to /dev/null,
  # even though there is no output being written to stderr by `nix shell`.
  _nix_prefetch_reply "$(nix eval --raw '(
    let pkgs = import <nixpkgs> { }; in
    with pkgs.lib;
    concatMapStrings (s: s + "\n") (filter (hasPrefix '"$str"') (attrNames pkgs))
  )' 2> /dev/null)"
}

_nix_prefetch() {
  # Indenting with spaces is required to still make " $prev_word " work.
  local params='
    -f --file -A --attr -E --expr -i --index -F --fetcher --arg --argstr -I --option
    -t --type --hash-algo -h --hash --input --output --eval
    --experimental-features --extra-experimental-features '
  local flags=' -s --silent -q --quiet -v --verbose -vv --debug -l --list --version ' flag
  for flag in --fetchurl --force-https --print-urls --print-path --compute-hash --check-store --autocomplete --help --deep; do
    flags+=" --no-${flag#--} $flag "
  done

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
      -E|--expr|-F|--fetcher|--eval)
        _nix_prefetch_reply "$(compgen -f -- "$curr_word")"
        _nix_prefetch_attrs "$curr_word"
        ;;
      -I)
        [[ $curr_word == *'='* ]] && _nix_prefetch_reply "$(compgen -f -- "${curr_word#*=}" | sed "s/^/${curr_word%%=*}=/")"
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
        local values='nix json shell raw'
        _nix_prefetch_reply "$(compgen -W "$values" -- "$curr_word")"
        ;;
    esac
    return 0
  fi

  (( COMP_CWORD == 1 )) && _nix_prefetch_all_args= || {
    local given_args all_args
    if [[ -n $_nix_prefetch_all_args ]]; then
      for word in "${COMP_WORDS[@]}"; do [[ $_nix_prefetch_all_args == *" $word "* ]] && given_args+=" $word"; done
      [[ -n $given_args ]] && given_args+=' '
    fi
    if [[ -z $_nix_prefetch_all_args || $given_args != $_nix_prefetch_given_args ]]; then
      _nix_prefetch_given_args=$given_args
      all_args=$(nix-prefetch --silent "${COMP_WORDS[@]:1:${#COMP_WORDS[@]} - 2}" --autocomplete) &&
        _nix_prefetch_all_args=" $(echo $all_args) " || _nix_prefetch_all_args=
    fi
  }

  _nix_prefetch_reply "$(compgen -f -- "$curr_word")"
  _nix_prefetch_attrs "$curr_word"
  _nix_prefetch_reply "$(compgen -W "$_nix_prefetch_all_args $params $flags" -- "$curr_word")"
}

complete -F _nix_prefetch nix-prefetch
