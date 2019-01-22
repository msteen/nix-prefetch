{ stdenv, makeWrapper, coreutils, gnugrep, nix }@args:

import ./. (args // { libShellVar = "./src"; })
