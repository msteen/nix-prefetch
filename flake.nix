{
  description = "nix-prefetch - Prefetch any fetcher function call, e.g. package sources";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in
      rec {
        packages.nix-prefetch = pkgs.callPackage ./default.nix {};
        defaultPackage = packages.nix-prefetch;
        apps.nix-prefetch = flake-utils.lib.mkApp { drv = packages.nix-prefetch; };
        defaultApp = apps.nix-prefetch;
      }
    );
}
