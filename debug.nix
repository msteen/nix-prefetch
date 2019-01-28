{ stdenv, makeWrapper, coreutils, gnugrep, gnused, jq, nix }@args:

import ./. (args // { libShellVar = "./src"; })
