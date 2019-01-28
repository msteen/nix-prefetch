# Used by:
# showFetcherHelp
# prefetch
# prefetchBuiltin

orig:

let lib = with lib; import ./common-nixpkgs.nix orig.nixpkgsPath // rec {
  hashEncodings = {
    base16 = {
      regex = "[a-f0-9]+";
      lengths = {
        md5    = 32;
        sha1   = 40;
        sha256 = 64;
        sha512 = 128;
      };
    };

    base32 = {
      regex = "[a-z0-9]+";
      lengths = {
        md5    = 26;
        sha1   = 32;
        sha256 = 52;
        sha512 = 103;
      };
    };

    base64 = {
      regex = "[A-Za-z0-9+/=]+";
      lengths = {
        md5    = 24;
        sha1   = 28;
        sha256 = 44;
        sha512 = 88;
      };
    };
  };

  hashAlgos = attrNames hashEncodings.base16.lengths;

  # The most obivous probably-wrong output hashes are zero valued output hashes, so they will be used.
  # The hashes are using base 32 encoding, because the actual output hash being reported in the hash mismatch error message
  # will also be using this encoding. For the purpose of having a probably-wrong output hash,
  # any other valid hash encoding would have been fine though.
  probablyWrongHashes = mapAttrs (_: length: repeatString length "0") hashEncodings.base32.lengths;

  writeLog = origLog: log: origLog + optionalString (!orig.quiet) log;

  isBuiltinFetcher = name: hasPrefix "builtins." name;

  toSource = x:
    if isSource x then x
    else if x ? srcs then if orig.index != null then elemAt x.srcs orig.index
      # If the index is undefined when it is actually needed, we choose to require to be explicit about it,
      # so instead of defaulting to 0, we throw an error.
      else throw "No index has been given, which is necessary to choose one of the multiple sources."
    else x.src or (throw "The expression could not be coerced to a source.");

  sourceURLs = src:
    if src ? urls then src.urls
    else if src ? url then [ src.url ]
    else [];

  exprFun = toExprFun orig.expr;
  expr = exprFun pkgs;
};

in with lib; let
  # We always have to determine the fetcher used by a package source,
  # because even if all we have to change is the hash, we cannot be sure a hash has already been given,
  # so it might throw an error before we can override its output hash.
  prefetchedSource =
    let
      customFetcherPackage = path: pkgArgs: let fun = import path pkgArgs; in (args: fun args // {
        __fetcher = {
          name = toString path;
          inherit args fun;
        };
      });

      fetcherFileNixpkgs =
        let
          customImport = scopedImport {
            import = path: if path == orig.fetcher.expr then customFetcherPackage path else customImport path;
          };
        in customImport nixpkgsPath { };

      fetcherFileSrc = toSource (exprFun fetcherFileNixpkgs);

      customFetcher = { name, path }: args: let fun = getAttrFromPath path pkgs; in fun args // {
        __fetcher = {
          inherit name args fun;
        };
      };

      fetchersNixpkgs =
        let
          customImport = scopedImport {
            import = path:
              let
                isFetcher = hasPrefix "fetch" (baseNameOf path);
                inNixpkgs = hasPrefix (toString nixpkgsPath + "/pkgs/") (toString path);
              in if isFetcher && inNixpkgs then customFetcherPackage path else customImport path;
          };

          fetchers = if orig.fetcher != null then [ orig.fetcher.expr ] else topLevelFetchers;

        in customImport nixpkgsPath {
          overlays = nixpkgsOverlays ++ [ (self: super: overlayFetchers fetchers customFetcher) ];
        };

      overriddenSrc = toSource (expr.override (origArgs:
        if orig.fetcher != null && orig.fetcher.type == "attr" then
          let name = last (splitString "." orig.fetcher.expr);
          in optionalAttrs (origArgs ? ${name}) (overlayFetchers [ orig.fetcher.expr ] customFetcher)
        else overlayFetchers (filter (name: pkgs ? ${name} && isFetcher name pkgs.${name}) (attrNames origArgs)) customFetcher
      ));

      overlainSrc = toSource (exprFun fetchersNixpkgs);

      prefetcher =
        # If the fetcher to be used was explicitly given, always try and use it.
        if orig.fetcher != null && orig.fetcher.type == "path" then if fetcherFileSrc ? __fetcher then applyFetcher fetcherFileSrc.__fetcher
          else throw "The fetcher file ${toString orig.fetcher.expr} was not used by the source."
        else if isPackage expr && overriddenSrc ? __fetcher then applyFetcher overriddenSrc.__fetcher
        else if overlainSrc ? __fetcher then applyFetcher overlainSrc.__fetcher
        else if orig.fetcher != null then throw "The fetcher ${toString orig.fetcher.expr} was not used by the source."
        else throw "Could not determine the fetcher used by the source.";

    in prefetcher (writeLog "" ''
      Prefetching ${expr.name}...
    '');

  prefetchedFetcher = if orig.fetcher != null
    then throw "The fetcher option should only be used in conjuction with a package derivation."
    else let
        nameExpr = exprFun (import nixpkgsPath {
          overlays = nixpkgsOverlays ++ [ (self: super: overlayFetchers (listFetchers true builtinPkgs ++ topLevelFetchers) ({ name, ... }: name)) ];
        });
        name = if isString nameExpr then nameExpr else "<unknown>";
      in applyFetcher { inherit name; fun = expr; args = {}; } (writeLog "" ''
        Prefetching with fetcher ${name}...
      '');

  applyFetcher = _fetcher: _log: let _orig = orig; in let orig = _orig // { fetcher = _fetcher; log = _log; }; in
    let
      fetcherArgs = mapAttrs (_: value: toExprFun value pkgs) orig.fetcherArgs;

      foundHashAlgos = intersectLists (attrNames fetcherArgs) hashAlgos;

      hashAlgo = maybeNull orig.hashAlgo (
        if orig.hash != null then let hashLength = stringLength hash; in findFirst (hashAlgo: hashAlgo != null)
          (throw "No hash algorithm encoding could be found that matches the length ${toString hashLength} of hash '${hash}'.")
          (mapAttrsToList (encoding: { regex, lengths }:
            findFirst (name: lengths.${name} == hashLength && builtins.match regex hash != null) null (attrNames lengths)
          ) hashEncodings)
        else if length foundHashAlgos == 1 then head foundHashAlgos
        else "sha256");

      hash =
        if orig.hash != null then if foundHashAlgos == [] then orig.hash
          else throw "No hashes should be given as fetcher arguments when an explicit hash has been given, yet the following were given: ${toAndList foundHashAlgos}."
        else if foundHashAlgos == [] then if orig.fetcher.args ? ${hashAlgo} then orig.fetcher.args.${hashAlgo}
          else probablyWrongHashes.${hashAlgo}
        else if foundHashAlgos == [ hashAlgo ] then fetcherArgs.${hashAlgo}
        else if length foundHashAlgos == 1 then throw "The ${head foundHashAlgos} hash given as a fetcher argument did not match the expected hash algorithm ${hashAlgo}."
          else throw "Only hashes of one algorithm are allowed, yet the following were given: ${toAndList foundHashAlgos}.";

      checkHash = foundHashAlgos == [] && orig.hash != null || foundHashAlgos == [ hashAlgo ];

      hashArgs = singleAttr hashAlgo hash;

      args = removeAttrs orig.fetcher.args hashAlgos // fetcherArgs // hashArgs;

      fetcher = {
        origArgPositions = mapAttrs (name: _: unsafeGetAttrPos name orig.fetcher.args) orig.fetcher.args;
        oldArgs = orig.fetcher.args;
        newArgs = fetcherArgs;
        hashArgs = hashArgs;
      } // (if orig.fetchURL then {
        name = "fetchurl";
        fun = pkgs.fetchurl;
        # FIXME: Check fetcher arguments for the URL.
        args = let urls = if isBuiltinFetcher orig.fetcher.name then [] else sourceURLs (orig.fetcher.fun args); in if urls != []
          then { url = head urls; } // optionalAttr args "name" // hashArgs
          else throw "The fetcher ${orig.fetcher.name} does not define any URLs.";
      } else {
        inherit (orig.fetcher) name fun;
        inherit args;
      });

      log = writeLog orig.log (
        let toPrettyCode = x: let s = toPretty x; in replaceStrings [ "\n" ] [ "\n>   " ] s;
        in ''
          The fetcher will be run as follows:
          > ${fetcher.name} {
          ${lines' (mapAttrsToList (name: value: ">   ${name} = ${toPrettyCode value};") fetcher.args)}
          > }

        '');

    in lib // {
      inherit expr exprFun;
      inherit fetcher hashAlgo hash checkHash log;
      actualHashSize = hashEncodings.base32.lengths.${hashAlgo};
      inherit (orig) quiet verbose debug;
    };

in if isFunction expr then prefetchedFetcher
else if isPackage expr || isSource expr then prefetchedSource
else throw "The expression does not resolve to either fetcher function, package derivation, or source derivation."
