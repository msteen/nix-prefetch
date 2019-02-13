`nix-prefetch`
===

This tool can be used to determine the hash of a fixed-output derivation, such as a package source. This can be used to apply TOFU in Nixpkgs (see TOFU below).
Besides determining the hash, you can also pass it a hash, and then it will validate it.
It should work with any fetcher function (function that produces a fixed-output derivation),
package derivations, or fixed-output derivations. In the case of the latter two (i.e. the derivations),
it will reuse the arguments already passed to the fetcher.

This tool is meant to help facilitate automatic update scripts.

TOFU
--

Trust-On-First-Use (TOFU) is a security model that will trust that, the response given by the non-yet-trusted endpoint,
is correct on first use and will derive an identifier from it to check the trustworthiness of future requests to the endpoint.
An well-known example of this is with SSH connections to hosts that are reporting a not-yet-known host key.
In the context of Nixpkgs, TOFU can be applied to fixed-output derivation (like produced by fetchers) to supply it with an output hash.
https://en.wikipedia.org/wiki/Trust_on_first_use

To implement the TOFU security model for fixed-output derivations the output hash has to determined at first build.
This can be achieved by first supplying the fixed-output derivation with a probably-wrong output hash,
that forces the build to fail with a hash mismatch error, which contains in its error message the actual output hash.

Installation
---

```
git clone https://github.com/msteen/nix-prefetch.git
cd nix-prefetch
nix-env --install --file release.nix
```

Planned features
---

* Try and see how many fetchers can be to not ignore certificate validity checking,
  without having to modify the fetchers themselves, to prevent potential man-in-the-middle (MITM) attacks when prefetching.

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

  Using import-from-derivation (IFD) or `builtins.exec` together with a rewriter based on `rnix` like `nix-update-fetch` does,
  we could in theory even handle this case, but it is not worth implementing at the moment,
  considering this is an edge case I have yet to encounter.

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
               [(-f | --file) <file>] [--fetch-url]
               [(-t | --type | --hash-algo) <hash-algo>] [(-h | --hash) <hash>]
               [--input <input-type>] [--output <output-type>] [--print-path]
               [--no-hash] [--force] [-s | --silent] [-q | --quiet] [-v | --verbose] [-vv | --debug] ...
               [<hash>]
               [--] [--<name> ((-f | --file) <file> | (-A | --attr) <attr> | (-E | --expr) <expr> | <str>) | --autocomplete <word> | --help] ...

Fetcher options (required):
  --owner
  --repo
  --rev

Fetcher options (optional):
  --curlOpts
  --downloadToTemp
  --executable
  --extraPostFetch
  --fetchSubmodules
  --githubBase
  --md5
  --meta
  --name
  --netrcImpureEnvVars
  --netrcPhase
  --outputHash
  --outputHashAlgo
  --passthru
  --postFetch
  --private
  --recursiveHash
  --sha1
  --sha256
  --sha512
  --showURLs
  --stripRoot
  --url
  --urls
  --varPrefix
```
