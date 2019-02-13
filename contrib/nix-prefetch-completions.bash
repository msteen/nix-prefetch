_nix_prefetch_reply() {
  [[ -n $1 ]] && mapfile -t -O "${#COMPREPLY}" COMPREPLY <<< "$1"
}

_nix_prefetch_attrs() {
  _nix_prefetch_reply "$(nix-instantiate --eval --strict --expr '{ currWord }:
    let pkgs = import <nixpkgs> { }; in with pkgs.lib;
    concatStringsSep "\n" (filter (hasPrefix currWord) (attrNames pkgs))
  ' --argstr currWord "$1" | jq . --raw-output)"
}

_nix_prefetch() {
  local params='-f --file -A --attr -E --expr -i --index -F --fetcher -t --type --hash-algo -h --hash --input --output'
  local flags='--fetch-url --print-path --no-hash --force --deep -l --list -q --quiet -v --verbose -vv --debug --help --version'

  COMPREPLY=()
  local prev_word=${COMP_WORDS[COMP_CWORD - 1]}
  local curr_word=${COMP_WORDS[COMP_CWORD]}

  if (( COMP_CWORD == 1 )); then
    _nix_prefetch_reply "$(compgen -f -- "$curr_word")"
    _nix_prefetch_attrs "$curr_word"
    return 0
  fi

  if (( COMP_CWORD > 1 )) && [[ $prev_word == -* && $params == *"$prev_word"* ]]; then
    local hash_algos='md5 sha1 sha256 sha512'
    local input_types='nix json shell'
    local output_types='expr nix json shell raw'
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
        _nix_prefetch_reply "$(compgen -W "$hash_algos" -- "$curr_word")"
        ;;
      --input)
        _nix_prefetch_reply "$(compgen -W "$input_types" -- "$curr_word")"
        ;;
      --output)
        _nix_prefetch_reply "$(compgen -W "$output_types" -- "$curr_word")"
        ;;
    esac
    return 0
  fi

  fetcher_args=$(nix-prefetch --silent "${COMP_WORDS[@]:1:${#COMP_WORDS[@]}-2}" --autocomplete "${COMP_WORDS[-1]#--}") &&
    _nix_prefetch_reply "$(sed s/^/--/ <<< "$fetcher_args")"

  _nix_prefetch_reply "$(compgen -W "$params $flags" -- "$curr_word")"
}

complete -F _nix_prefetch nix-prefetch
