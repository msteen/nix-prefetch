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
100  708k  100  708k    0     0  1047k      0 --:--:-- --:--:-- --:--:-- 1047k

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

The following URLs will be fetched as part of the source:
https://www.kernel.org/pub/software/scm/git/git-2.18.1.tar.xz

trying https://www.kernel.org/pub/software/scm/git/git-2.18.1.tar.xz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   178  100   178    0     0   1424      0 --:--:-- --:--:-- --:--:--  1424
100 4983k  100 4983k    0     0  10.1M      0 --:--:-- --:--:-- --:--:-- 24.4M

1dlq120c9vmvp1m9gmgd6m609p2wkgfkljrpb0i002mpbjj091c8
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
>   src = /nix/store/qbnf8r6y26z7865milkz7dsmq6z0aqps-nix-prefetch-0.1.0/contrib/hello_rs;
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
