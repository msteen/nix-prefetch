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
$ nix-prefetch test 
The package test-0.1.0 will be fetched as follows:
> fetchurl {
>   name = "foo";
>   sha256 = "0000000000000000000000000000000000000000000000000000";
>   url = "https://gist.githubusercontent.com/msteen/fef0b259aa8e26e9155fa0f51309892c/raw/112c7d23f90da692927b76f7284c8047e50fdc14/test.txt";
> }

0jsvhyvxslhyq14isbx2xajasisp7xdgykl0dffy3z1lzxrv51kb
```

A package with verbose output:
```
$ nix-prefetch hello --verbose 
The package hello-2.10 will be fetched as follows:
> fetchurl {
>   sha256 = "0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i";
>   url = "mirror://gnu/hello/hello-2.10.tar.gz";
> }

The following URLs will be fetched as part of the source:
mirror://gnu/hello/hello-2.10.tar.gz

trying http://ftpmirror.gnu.org/hello/hello-2.10.tar.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100  708k  100  708k    0     0  1498k      0 --:--:-- --:--:-- --:--:-- 1498k

0ssi1wpaf7plaswqqjwigppsg5fyh99vdlb9kzl7c9lng89ndq1i
```

Modify the Git revision of a call to `fetchFromGitHub`:
```
$ nix-prefetch openraPackages.engines.bleed --fetch-url --rev master 
error: undefined variable 'openraPackages' at (string):4:85
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
>   src = /nix/store/bscncp1f7y0zakkx6h3ayxxd2zkcgk45-nix-prefetch-0.2.0/contrib/hello_rs;
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
               [(-f | --file) <file>] [--fetchurl]
               [(-t | --type | --hash-algo) <hash-algo>] [(-h | --hash) <hash>]
               [--input <input-type>] [--output <output-type>] [--print-urls] [--print-path]
               [--compute-hash] [--force] [-s | --silent] [-q | --quiet] [-v | --verbose] [-vv | --debug] ...
               ([-f | --file] <file> | [-A | --attr] <attr> | [-E | --expr] <expr> | <url>) [<hash>]
               [--] [--<name> ((-f | --file) <file> | (-A | --attr) <attr> | (-E | --expr) <expr> | <str>) | --autocomplete | --help] ...

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

