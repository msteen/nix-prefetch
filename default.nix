{ stdenv, makeWrapper, coreutils, gnugrep, gnused, jq, nix, libShellVar ? "$lib" }:

with stdenv.lib;

stdenv.mkDerivation rec {
  name = "${pname}-${version}";
  pname = "nix-prefetch";
  version = "0.1.0";

  src = ./src;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    lib=$out/lib/${pname}
    mkdir -p $out/bin $lib
    substitute ${pname}.sh $lib/${pname}.sh \
      --subst-var-by lib ${libShellVar} \
      --subst-var-by version '${version}'
    chmod +x $lib/${pname}.sh
    patchShebangs $lib/${pname}.sh
    makeWrapper $lib/${pname}.sh $out/bin/${pname} \
      --prefix PATH : '${makeBinPath [ coreutils gnugrep gnused jq nix ]}'
    cp write_file.sh $lib/
    cp *.nix $lib/
  '';

  meta = {
    description = "Prefetch any fetcher function call, e.g. a package source";
    homepage = https://github.com/msteen/nix-prefetch;
    license = licenses.mit;
    maintainers = with maintainers; [ msteen ];
    platforms = platforms.all;
  };
}
