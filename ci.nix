with import <nixpkgs> {};
mkShell {
  nativeBuildInputs = [
    coreutils bash gawk gnugrep gnused jq nix git
  ];

  shellHook = ''
    set -e
    echo -e "\x1b[32m## run test suite\x1b[0m"
    bash ./src/tests.sh
  '';
}
