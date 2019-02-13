{ lib, pkgs, fetcher }:

with lib;

let
  fetcherExprFun = pkgs:
    if fetcher.type == "attr" then getAttrFromPath (splitString "." fetcher.name) pkgs
    else if fetcher.type == "file" then importFetcher pkgs fetcher.name
    else throw "Unsupported fetcher type '${type}'.";

  markFetcherDrv = { name, value, args, drv, ... }: drv.overrideAttrs (origAttrs: {
    passthru = origAttrs.passthru or {} // {
      __fetcherFunctionArgs = drv.__fetcherFunctionArgs or {}
        // applyIf (name != fetcher.name) (mapAttrs (name: isOptional: isOptional || args ? ${name})) (functionArgs value);
    };
  });

  fetcherFromOverlay = fetcherExprFun (fetcherDrvNixpkgs pkgs pkgs.topLevelFetchers markFetcherDrv);

  fetcherArgs = mapAttrs (_: _: "") (filterAttrs (_: isOptional: !isOptional) (functionArgs fetcher.value));

in (fetcherFromOverlay fetcherArgs).__fetcherFunctionArgs
