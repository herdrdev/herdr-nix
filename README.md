# herdr-nix

Official Nix packaging for Herdr's prebuilt GitHub Release binaries.

## Contents

- [Why this exists](#why-this-exists)
- [Usage](#usage)
- [Configuration / API](#configuration--api)
- [Staying current](#staying-current)
- [Contributing](#contributing)
- [Provenance](#provenance)
- [Licensing](#licensing)

## Why this exists

herdr's own [documented Nix install instructions](https://herdr.dev/docs/install/#install-with-nix)
point at its source flake (`nix run|build|profile install github:herdrdev/herdr/vX.Y.Z`) — which
builds herdr from source, pulling in the full Rust + Zig toolchain, on every install and every
update. There's no binary cache behind it, so that source build repeats for every consumer,
every time. That's especially unwelcome in a devenv context, where the shell can rebuild often.

This repo instead fetches herdr's own prebuilt, per-platform release binaries
(`herdr-linux-x86_64`, `herdr-linux-aarch64`, `herdr-macos-x86_64`, `herdr-macos-aarch64` —
published by herdr's own `release.yml` on every tagged release) and wraps them in a Nix
derivation. No compilation, no toolchain, just a hash-verified download.

After a version update passes review and CI, builds from protected `main` are pushed to the
public Cachix cache (`herdr`). Pull requests never receive cache credentials.

## Usage

### With devenv

Add the flake input and pull the `herdr` Cachix cache declaratively — devenv wires the
substituter and trusted public key for you, no manual `nix.conf` editing:

```yaml
# devenv.yaml
inputs:
  herdr-nix:
    url: github:herdrdev/herdr-nix
```

```nix
# devenv.nix
{ pkgs, inputs, ... }:

{
  cachix.pull = [ "herdr" ];

  packages = [
    inputs.herdr-nix.packages.${pkgs.stdenv.system}.default
  ];
}
```

`devenv shell` then pulls `herdr` straight from the cache instead of building it.

### Standalone Nix (flakes)

```nix
{
  inputs.herdr-nix.url = "github:herdrdev/herdr-nix";
  # ...
  # inputs.herdr-nix.packages.${system}.default
}
```

Or run it directly without adding an input:

```sh
nix run github:herdrdev/herdr-nix
```

To pull from the cache instead of building, add the substituter to your user/system
`nix.conf` (or `~/.config/nix/nix.conf`):

```
extra-substituters = https://herdr.cachix.org
extra-trusted-public-keys = herdr.cachix.org-1:3nH7IStRsS0ASfdonA0DCRR2ZrSCeWitZ7Kwew0cR4I=
```

Or, if you're consuming this as a flake input and have `accept-flake-config = true` set
(or answer `y` to the one-time prompt), declare it in your own `flake.nix` instead so
consumers of *your* flake pick it up too:

```nix
{
  nixConfig = {
    extra-substituters = [ "https://herdr.cachix.org" ];
    extra-trusted-public-keys = [ "herdr.cachix.org-1:3nH7IStRsS0ASfdonA0DCRR2ZrSCeWitZ7Kwew0cR4I=" ];
  };
}
```

To verify that key against the cache itself, run `cachix use herdr` (it writes the same
substituter and key into your `nix.conf`), or read it straight from the API:

```sh
curl -s https://cachix.org/api/v1/cache/herdr
```

## Configuration / API

This is a plain package flake — no NixOS/devenv module options, nothing to configure beyond
picking a system. It exposes:

| Output | Type | Notes |
|---|---|---|
| `packages.<system>.herdr` | derivation | The herdr binary, installed at `bin/herdr`. |
| `packages.<system>.default` | derivation | Alias for `packages.<system>.herdr`. |
| `apps.<system>.default` | app | `nix run` wrapper around `bin/herdr`. |
| `checks.<system>.herdr` | derivation | Same build, exercised by `nix flake check`. |

Supported `<system>`: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin` —
matching herdr's own published release assets. The pinned `version` and per-asset hashes live
in [`package.nix`](package.nix); there is no override mechanism for the version — bump it via
`update.sh` (see below) rather than `overrideAttrs`, since the hash is tied 1:1 to the pinned
version.

## Staying current

`update.sh` checks herdr's latest **stable** release (tagged `vX.Y.Z`; the frequent
`preview-*` pre-releases are intentionally skipped) and rewrites `package.nix` with the new
version and per-platform hashes. The `update-check` GitHub Actions workflow runs this daily
and opens a PR when a new stable release is found — no manual hash-bumping needed.

Run it by hand:

```sh
./update.sh
nix flake check
```

## Contributing

Issues and PRs are welcome, particularly reports of upstream release-asset changes or a Herdr
version that breaks `update.sh`'s detection.

## Provenance

[@tburny](https://github.com/tburny) created this packaging and transferred it to the Herdr
project in 2026. It remains a separate repository because it packages release binaries rather
than building Herdr from source.

## Licensing

This repo's own packaging code (`flake.nix`, `package.nix`, `update.sh`, CI) is MIT-licensed
— see [`LICENSE`](LICENSE). The herdr binaries this repo fetches and distributes are themselves
licensed under AGPL-3.0-or-later by their upstream project; see
[Herdr's LICENSE](https://github.com/herdrdev/herdr/blob/master/LICENSE) for the terms that
apply to the binary itself.
