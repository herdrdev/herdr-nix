{
  description = "Official Nix packaging for Herdr release binaries";

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

        checks = {
          inherit herdr;
          scripts = pkgs.runCommand "herdr-nix-scripts" {
            nativeBuildInputs = [
              pkgs.bats
              pkgs.python3
              pkgs.shellcheck
            ];
          } ''
            cp -R ${./.} source
            chmod -R u+w source
            cd source
            shellcheck update.sh
            bats tests
            touch "$out"
          '';
        };
      }
    );
}
