{
  description = "Unofficial Nix packaging for herdr, fetched from upstream GitHub Releases (no from-source build)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        herdr = pkgs.callPackage ./package.nix { };
      in
      {
        packages = {
          inherit herdr;
          default = herdr;
        };

        apps.default = {
          type = "app";
          program = "${herdr}/bin/herdr";
        };

        checks.herdr = herdr;
      }
    );
}
