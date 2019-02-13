{ stdenv, makeWrapper
, asciidoc, docbook_xml_dtd_45, docbook_xsl, libxml2, libxslt
, coreutils, gawk, gnugrep, gnused, jq, nix }:

with stdenv.lib;

stdenv.mkDerivation rec {
  name = "${pname}-${version}";
  pname = "nix-prefetch";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
    asciidoc docbook_xml_dtd_45 docbook_xsl libxml2 libxslt
  ];

  configurePhase = ''
    . configure.sh
  '';

  buildPhase = ''
    a2x -f manpage doc/nix-prefetch.1.asciidoc
  '';

  installPhase = ''
    lib=$out/lib/${pname}
    mkdir -p $lib
    substitute lib/main.sh $lib/main.sh \
      --subst-var-by lib $lib \
      --subst-var-by version '${version}'
    chmod +x $lib/main.sh
    patchShebangs $lib/main.sh
    cp lib/*.nix $lib/

    mkdir -p $out/bin
    makeWrapper $lib/main.sh $out/bin/${pname} \
      --prefix PATH : '${makeBinPath [ coreutils gawk gnugrep gnused jq nix ]}'

    mkdir -p $out/share/man/man1
    substitute doc/nix-prefetch.1 $out/share/man/man1/nix-prefetch.1 \
      --subst-var-by version '${version}' \
      --replace '01/01/1970' "$date"

    install -D contrib/nix-prefetch-completion.bash $out/share/bash-completion/completions/nix-prefetch
    install -D contrib/nix-prefetch-completion.zsh $out/share/zsh/site-functions/_nix_prefetch
  '';

  meta = {
    description = "Prefetch any fetcher function call, e.g. a package source";
    homepage = https://github.com/msteen/nix-prefetch;
    license = licenses.mit;
    maintainers = with maintainers; [ msteen ];
    platforms = platforms.all;
  };
}
