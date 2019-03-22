`nix-prefetch`
===

This tool can be used to determine the hash of a fixed-output derivation, such as a package source. This can be used to apply TOFU in Nixpkgs (see TOFU below).
Besides determining the hash, you can also pass it a hash, and then it will validate it.
It should work with any fetcher function (function that produces a fixed-output derivation),
package derivations, or fixed-output derivations. In the case of the latter two (i.e. the derivations),
it will reuse the arguments already passed to the fetcher.

The tool relies on an overlay to hijack calls made to the fetchers and to patch them to ignore insecure flags (those that disable certificate checking).
However it is possible that the particular fetcher used by a package was detected not to be a fetcher function, so for those edge cases there is the `--fetcher` option (see manpage).

Use cases for this tool include determining the hash of a new package version, automated update scripts, and inspecting the current argument passed to a fetcher.

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

Features
---

* Can work with any fetcher function, even those defined outside Nixpkgs.

* Can work with any package that defines a `src` or `srcs` attribute based on a fetcher.

* Supports the builtin fetchers, like `builtins.fetchurl`.

* Automatically calls `callPackage { }` whenever this is applicable.

* Monkey patches the fetchers (via an overlay) to not ignore certificate validity checking,
  to reduce the risk of man-in-the-middle (MITM) attacks when prefetching.

* Automatically determines the default Git revision when none have been given.

* Completions for `bash` and `zsh`, including autocomplete for the fetcher arguments.

* Knows how fetchers are often built on top of other fetchers, and if this is the case, will report fetcher arguments as well in the autocomplete and help.

* Not only allows passing string arguments to the fetcher, but any arbitrary Nix expression as well, e.g. `--count --expr 5`.

* Boolean fetcher arguments can be given as flags, so you can do `--showURLs` or `--no-showURLs` rather than `--showURLs --expr true` or `--showURLs --expr false`, respectively.

* When the `--check-store` option has been given, it will not redownload the source if you already have something installed that uses the source.

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
The fetcher will be called as follows:
> fetchurl {
>   sha256 = "0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i";
>   url = "mirror://gnu/hello/hello-2.10.tar.gz";
> }

0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i
```

A package without a hash defined:
```
$ nix-prefetch '{ stdenv, fetchurl }: stdenv.mkDerivation rec {
                  name = "test";
                  src = fetchurl { url = http://ftpmirror.gnu.org/hello/hello-2.10.tar.gz; };
                }' 
The package test will be fetched as follows:
> fetchurl {
>   sha256 = "0000000000000000000000000000000000000000000000000000";
>   url = "https://ftpmirror.gnu.org/hello/hello-2.10.tar.gz";
> }

0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i
```

A package checked to already be in the Nix store thats not installed:
```
$ nix-prefetch hello --check-store --verbose 
The package hello-2.10 will be fetched as follows:
> fetchurl {
>   sha256 = "0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i";
>   url = "mirror://gnu/hello/hello-2.10.tar.gz";
> }

The following URLs will be fetched as part of the source:
mirror://gnu/hello/hello-2.10.tar.gz

trying https://ftpmirror.gnu.org/hello/hello-2.10.tar.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100  708k  100  708k    0     0  1102k      0 --:--:-- --:--:-- --:--:-- 1102k

0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i
```

A package checked to already be in the Nix store thats installed (i.e. certain the hash is valid, no need to redownload):
```
$ nix-prefetch git --check-store --verbose 
The package git-minimal-2.18.1 will be fetched as follows:
> fetchurl {
>   sha256 = "1dlq120c9vmvp1m9gmgd6m609p2wkgfkljrpb0i002mpbjj091c8";
>   url = "https://www.kernel.org/pub/software/scm/git/git-2.18.1.tar.xz";
> }

1dlq120c9vmvp1m9gmgd6m609p2wkgfkljrpb0i002mpbjj091c8
```

Passing a list rather than a string argument:
```
$ nix-prefetch fetchurl --urls --expr '[ mirror://gnu/hello/hello-2.10.tar.gz ]' 
The fetcher will be called as follows:
> fetchurl {
>   sha256 = "0000000000000000000000000000000000000000000000000000";
>   urls = [ "mirror://gnu/hello/hello-2.10.tar.gz" ];
> }

0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i
```

Modify the Git revision of a call to `fetchFromGitHub`:
```
$ nix-prefetch openraPackages.engines.bleed --fetchurl --rev master 
The package openra-bleed-9c9cad1 will be fetched as follows:
> fetchurl {
>   sha256 = "0100p7wrnnlvkmy581m0gbyg3cvi4i1w3lzx2gq91ndz1sbm8nd2";
>   url = "https://github.com/OpenRA/OpenRA/archive/master.tar.gz";
> }

0sj8ac3vm8dwxzr7krq4gz4pdmzbiv31q20ca17jyzn0sxfddr81
```

Hash validation:
```
$ nix-prefetch hello 0000000000000000000000000000000000000000000000000000 
The package hello-2.10 will be fetched as follows:
> fetchurl {
>   sha256 = "0000000000000000000000000000000000000000000000000000";
>   url = "mirror://gnu/hello/hello-2.10.tar.gz";
> }

error: A hash mismatch occurred for the fixed-output derivation output /nix/store/57fzizqf6658l22j247vka6ljbicvkzj-hello-2.10.tar.gz:
  expected: 0000000000000000000000000000000000000000000000000000
    actual: 0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i
```

A specific file fetcher:
```
$ nix-prefetch hello_rs.cargoDeps --fetcher '<nixpkgs/pkgs/build-support/rust/fetchcargo.nix>' 
The fetcher will be called as follows:
> import /wheel/fork/nixpkgs/pkgs/build-support/rust/fetchcargo.nix {
>   cargoUpdateHook = "";
>   name = "hello_rs-0.1.0";
>   patches = [  ];
>   sha256 = "0sjjj9z1dhilhpc8pq4154czrb79z9cm044jvn75kxcjv6v5l2m5";
>   sourceRoot = null;
>   src = /nix/store/sd0j1kma94ss1ikqf4917fmbm72l3793-nix-prefetch-0.1.0/contrib/hello_rs;
>   srcs = null;
> }

0sjjj9z1dhilhpc8pq4154czrb79z9cm044jvn75kxcjv6v5l2m5
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
fetchTarball
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
requireFile
```

Get a specialized help message for a fetcher:
```
$ nix-prefetch fetchFromGitHub --help 
Prefetch the fetchFromGitHub function call

Usage:
  nix-prefetch fetchFromGitHub
               [(-f | --file) <file>] [--fetchurl] [--force-https]
               [(-t | --type | --hash-algo) <hash-algo>] [(-h | --hash) <hash>]
               [--input <input-type>] [--output <output-type>] [--print-urls] [--print-path]
               [--compute-hash] [--check-store] [-s | --silent] [-q | --quiet] [-v | --verbose] [-vv | --debug] ...
               ([-f | --file] <file> | [-A | --attr] <attr> | [-E | --expr] <expr> | <url>) [<hash>]
               [--help | --autocomplete | --eval <expr>]
               [--] [--<name> ((-f | --file) <file> | (-A | --attr) <attr> | (-E | --expr) <expr> | <str>)] ...

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

A package for i686-linux:
```
$ nix-prefetch '(import <nixpkgs> { system = "i686-linux"; }).scilab-bin' 
The package scilab-bin-6.0.1 will be fetched as follows:
> fetchurl {
>   sha256 = "0fgjc2ak3b2qi6yin3fy50qwk2bcj0zbz1h4lyyic9n1n1qcliib";
>   url = "https://www.scilab.org/download/6.0.1/scilab-6.0.1.bin.linux-i686.tar.gz";
> }

0fgjc2ak3b2qi6yin3fy50qwk2bcj0zbz1h4lyyic9n1n1qcliib
```
