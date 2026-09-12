{
  description = "Official Nix packaging for Herdr release binaries";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      systems = [
        "x86_64-linux"
        "i686-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          herdr = pkgs.callPackage ./package.nix { };
          default = herdr;
        }
      );

      apps.default = forAllSystems (system: {
        type = "app";
        program = nixpkgs.lib.getExe self.packages.${system}.default;
      });

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          herdr = self.packages.${system}.herdr;
          scripts =
            pkgs.runCommand "herdr-nix-scripts"
              {
                nativeBuildInputs = [
                  pkgs.bats
                  pkgs.python3
                  pkgs.shellcheck
                ];
              }
              ''
                cp -R ${./.} source
                chmod -R u+w source
                cd source
                shellcheck update.sh
                bats tests
                touch "$out"
              '';
        }
      );
    };
}
