{ pkgs, lib, config, ... }:

{
  cachix.pull = [ "devenv" "nix-community" ];

  packages = [
    pkgs.gh
    pkgs.python3
    pkgs.cachix
    pkgs.shellcheck
  ] ++ lib.optionals config.devenv.isTesting [
    pkgs.bats
  ];

  enterShell = ''
    echo "herdr-nix dev shell — nix build .#default | ./update.sh | shellcheck update.sh"
  '';

  enterTest = ''
    shellcheck update.sh
    bats tests/
    nix flake check
  '';
}
