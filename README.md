`nix-prefetch`
===

This tool can be used to determine the hash of a fixed-output derivation, such as a package source.
Besides determining the hash, you can also pass it a hash, and then it will validate it.
It should work with any fetcher function (function that produces a fixed-output derivation),
package derivations, or fixed-output derivations. In the case of the latter two (i.e. the derivations),
it will reuse the arguments already passed to the fetcher.

This tool is meant to help facilitate automatic update scripts.

Installation
---

```
git clone https://github.com/msteen/nix-prefetch.git
cd nix-prefetch
nix-env --install --file release.nix
```

Planned features
---

* Keep the failed build around to prevent the need to re-download the sources
  and automatically rebuild the source with the corrected hash.
  This is especially useful for big downloads.

* Implement support for the builtin fetchers (see Limitations).

Limitations
---

* If the fetcher used by a source is not packaged as a file,
  it is not possible to determine the original arguments passed to it.

  For example the following will not work:

  ```nix
  let fetcher = stdenv.mkDerivation { outputHash = "..."; };
  in stdenv.mkDerivation {
    src = fetcher {
      foo = 5;
    };
  }
  ```

  We would not be able to extract that `{ foo = 5; }` was passed to the fetcher.

* If a fetcher is based on another fetcher, we will not be able to list all its possible arguments
  in the fetcher's help message.

* The builtin fetchers will build a derivation and realize it immediately,
  while the implementation expects to do those things seperately.
  By making a special case for the builtins this could be worked around,
  but at the moment builtin fetchers are not supported.

Examples
---

A package source:

```
$ nix-prefetch hello.src
Prefetching source hello-2.10.tar.gz...
The fetcher will be run as follows:
> fetchurl {
>   sha256 = "0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i";
>   url = "mirror://gnu/hello/hello-2.10.tar.gz";
> }

The following URLs will be fetched as part of the source:
mirror://gnu/hello/hello-2.10.tar.gz

0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i
```

A package without a hash defined:

```
$ nix-prefetch test
Prefetching package test-0.1.0...
The fetcher will be run as follows:
> fetchurl {
>   name = "foo";
>   sha256 = "0000000000000000000000000000000000000000000000000000";
>   url = "https://gist.githubusercontent.com/msteen/fef0b259aa8e26e9155fa0f51309892c/raw/112c7d23f90da692927b76f7284c8047e50fdc14/test.txt";
> }

The following URLs will be fetched as part of the source:
https://gist.githubusercontent.com/msteen/fef0b259aa8e26e9155fa0f51309892c/raw/112c7d23f90da692927b76f7284c8047e50fdc14/test.txt

0jsvhyvxslhyq14isbx2xajasisp7xdgykl0dffy3z1lzxrv51kb
```

Modify the Git revision of a call to `fetchFromGitHub`:

```
$ nix-prefetch openraPackages.engines.bleed --fetch-url --rev master
Prefetching package openra-bleed-6de92de...
The fetcher will be run as follows:
> fetchurl {
>   sha256 = "0p0izykjnz7pz02g2khp7msqa00jhjsrzk9y0g29dirmdv75qa4r";
>   url = "https://github.com/OpenRA/OpenRA/archive/master.tar.gz";
> }

The following URLs will be fetched as part of the source:
https://github.com/OpenRA/OpenRA/archive/master.tar.gz

0sj8ac3vm8dwxzr7krq4gz4pdmzbiv31q20ca17jyzn0sxfddr81
```

Hash validation:

```
$ nix-prefetch hello 0000000000000000000000000000000000000000000000000000
Prefetching package hello-2.10...
The fetcher will be run as follows:
> fetchurl {
>   sha256 = "0000000000000000000000000000000000000000000000000000";
>   url = "mirror://gnu/hello/hello-2.10.tar.gz";
> }

The following URLs will be fetched as part of the source:
mirror://gnu/hello/hello-2.10.tar.gz

Error: A hash mismatch occurred for the fixed-output derivation output '/nix/store/g1wa5ywm1cf8530fd2j92a9d7pcb0dx3-hello-2.10.tar.gz':
  expected: 0000000000000000000000000000000000000000000000000000
    actual: 0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i
```

A specific file fetcher:

```
$ nix-prefetch du-dust.cargoDeps --fetcher '<nixpkgs/pkgs/build-support/rust/fetchcargo.nix>'
Prefetching source dust-0.2.3-vendor...
The fetcher will be run as follows:
> /nix/store/sx4gggi0fx6cp2lx7klkk2vp2x2vank0-fetchcargo.nix {
>   cargoUpdateHook = "";
>   name = "dust-0.2.3";
>   patches = [  ];
>   sha256 = "0x3ay440vbc64y3pd8zhd119sw8fih0njmkzpr7r8wdw3k48v96m";
>   sourceRoot = null;
>   src = <δ:source>;
>   srcs = null;
> }

0x3ay440vbc64y3pd8zhd119sw8fih0njmkzpr7r8wdw3k48v96m
```

List all known fetchers in Nixpkgs:

```
$ nix-prefetch --list --deep
builtins.fetchGit
builtins.fetchMercurial
builtins.fetchTarball
builtins.fetchurl
elmPackages.fetchElmDeps
fetchCrate
fetchDockerConfig
fetchDockerLayer
fetchFromBitbucket
fetchFromGitHub
fetchFromGitLab
fetchFromRepoOrCz
fetchFromSavannah
fetchHex
fetchMavenArtifact
fetchNuGet
fetchRepoProject
fetchbower
fetchbzr
fetchcvs
fetchdarcs
fetchdocker
fetchegg
fetchfossil
fetchgit
fetchgitLocal
fetchgitPrivate
fetchgx
fetchhg
fetchipfs
fetchmtn
fetchpatch
fetchs3
fetchsvn
fetchsvnrevision
fetchsvnssh
fetchurl
fetchurlBoot
fetchzip
javaPackages.fetchMaven
javaPackages.mavenPlugins.fetchMaven
lispPackages.fetchurl
python27Packages.fetchPypi
python36Packages.fetchPypi
```

Get a specialized help message for a fetcher:

```
$ nix-prefetch fetchFromGitHub --help
The fetcher fetchFromGitHub produces a fixed-output derivation to use as a source.

All options can be repeated with the last value taken,
and can placed both before and after the parameters.

To keep the usage section simple, the possible fetcher options have not been listed.
They can be found in their own sections instead.

Usage:
  nix-prefetch fetchFromGitHub
               [ -f <file> | --file <file>
               | -t <hash-algo> | --type <hash-algo> | --hash-algo <hash-algo>
               | -h <hash> | --hash <hash>
               | --fetch-url | --print-path | --force
               | -q | --quiet | -v | --verbose | -vv | --debug | --skip-hash ]...
               [hash]
               [--]
               ( <fetcher-option>
                 ( -f <file> | --file <file>
                 | -A <attr> | --attr <attr>
                 | -E <expr> | --expr <expr>
                 | <str> ) )...
  nix-prefetch [-v | --verbose | -vv | --debug] fetchFromGitHub --help

Fetcher options (required):
  --owner
  --repo
  --rev

Fetcher options (optional):
  --fetchSubmodules
  --githubBase
  --name
  --private
  --varPrefix

Options:
  -f, --file       When either an attribute or expression is given it has to be a path to Nixpkgs,
                  otherwise it can be a file directly pointing to a fetcher function or package derivation.
  -t, --type,
      --hash-algo  What algorithm should be used for the output hash of the resulting derivation.
  -h, --hash       When the output hash of the resulting derivation is already known,
                  it can be used to check whether it is already exists within the Nix store.
  --fetch-url      Fetch only the URL. This converts e.g. the fetcher fetchFromGitHub to fetchurl for its URL,
                  and the hash options will be applied to fetchurl instead. The name argument will be copied over.
  --print-path     Print the output path of the resulting derivation.
  --force          Always redetermine the hash, even if the given hash is already determined to be valid.
  -q, --quiet      No additional output.
  -v, --verbose    Verbose output, so it is easier to determine what is being done.
  -vv, --debug     Even more verbose output (meant for debugging purposes).
  --skip-hash      Skip determining the hash (meant for debugging purposes).
  --help           Show help message.
```

Help message
---

```
Prefetch any fetcher function call, e.g. a package source.

All options can be repeated with the last value taken,
and can placed both before and after the parameters.

Usage:
  nix-prefetch [ -f <file> | --file <file>
               | -A <attr> | --attr <attr>
               | -E <expr> | --expr <expr>
               | -i <index> | --index <index>
               | -F (<file> | <attr>) | --fetcher (<file> | <attr>)
               | -t <hash-algo> | --type <hash-algo> | --hash-algo <hash-algo>
               | -h <hash> | --hash <hash>
               | --fetch-url | --print-path | --force
               | -q | --quiet | -v | --verbose | -vv | --debug | --skip-hash ]...
               ( -f <file> | --file <file> | <file>
               | -A <attr> | --attr <attr> | <attr>
               | -E <expr> | --expr <expr> | <expr>
               | <url> )
               [hash]
               [--]
               [ --<name>
                 ( -f <file> | --file <file>
                 | -A <attr> | --attr <attr>
                 | -E <expr> | --expr <expr>
                 | <str> ) ]...
  nix-prefetch [-f <file> | --file <file> | --deep | -v | --verbose | -vv | --debug]... (-l | --list)
  nix-prefetch --help
  nix-prefetch [-v | --verbose | -vv | --debug] (-f <file> | --file <file> | <attr>) --help
  nix-prefetch --version

Examples:
  nix-prefetch hello
  nix-prefetch hello --hash-algo sha512
  nix-prefetch hello.src
  nix-prefetch 'let name = "hello"; in pkgs.${name}'
  nix-prefetch 'callPackage (pkgs.path + /pkgs/applications/misc/hello) { }'
  nix-prefetch --file '<nixos-unstable>' hello
  nix-prefetch hello 0000000000000000000000000000000000000000000000000000
  nix-prefetch du-dust.cargoDeps --fetcher --file '<nixpkgs/pkgs/build-support/rust/fetchcargo.nix>'

Options:
  -f, --file       When either an attribute or expression is given it has to be a path to Nixpkgs,
                   otherwise it can be a file directly pointing to a fetcher function or package derivation.
  -A, --attr       An attribute path relative to the `pkgs` of the imported Nixpkgs.
  -E, --expr       A Nix expression with the `pkgs` of the imported Nixpkgs put into scope,
                   evaluating to either a fetcher function or package derivation.
  -i, --index      Which element of the list of sources should be used when multiple sources are available.
  -F, --fetcher    When the fetcher of the source cannot be automatically determined,
                   this option can be used to pass it manually instead.
  -t, --type,
      --hash-algo  What algorithm should be used for the output hash of the resulting derivation.
  -h, --hash       When the output hash of the resulting derivation is already known,
                   it can be used to check whether it is already exists within the Nix store.
  --fetch-url      Fetch only the URL. This converts e.g. the fetcher fetchFromGitHub to fetchurl for its URL,
                   and the hash options will be applied to fetchurl instead. The name argument will be copied over.
  --print-path     Print the output path of the resulting derivation.
  --force          Always redetermine the hash, even if the given hash is already determined to be valid.
  -q, --quiet      No additional output.
  -v, --verbose    Verbose output, so it is easier to determine what is being done.
  -vv, --debug     Even more verbose output (meant for debugging purposes).
  --skip-hash      Skip determining the hash (meant for debugging purposes).
  --deep           Rather than only listing the top-level fetchers, deep search Nixpkgs for fetchers (slow).
  -l, --list       List the available fetchers in Nixpkgs.
  --version        Show version information.
  --help           Show help message.

Note: This program is EXPERIMENTAL and subject to change.
```
