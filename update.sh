#!/usr/bin/env bash
# Bumps the pinned packages to their latest stable releases, rewriting the
# version and per-platform hashes in place:
#   herdr       package.nix      latest stable GitHub release (skips `preview-*`)
#   herdr-core  herdr-core.nix   releases.herdr.dev/core/latest.json
#   herdr-app   herdr-app.nix    releases.herdr.dev/app/latest.json
# With no arguments it updates all three. Run locally or through the
# `update-check` workflow, which validates all platforms before committing
# and publishing.
set -euo pipefail

dir="$(dirname "$0")"
releases="${HERDR_RELEASES_URL:-https://releases.herdr.dev}"

pinned_version() {
  grep -m1 '^  version = ' "$1" | sed -E 's/.*"([^"]+)".*/\1/'
}

# set_hash <file> <asset> <sri>: the hash on the line after `name = "<asset>";`.
set_hash() {
  python3 - "$1" "$2" "$3" <<'PYEOF'
import re, sys
path, asset, sri = sys.argv[1:4]
text = open(path).read()
pattern = re.compile(
    r'(name = "%s";\s*\n\s*hash = ")[^"]+(";)' % re.escape(asset)
)
text, n = pattern.subn(lambda m: m.group(1) + sri + m.group(2), text)
if n != 1:
    sys.exit(f"update.sh: expected exactly one match for {asset}, got {n}")
open(path, "w").write(text)
PYEOF
}

set_version() {
  sed -i -E "s/^(  version = )\"[^\"]+\";/\1\"$2\";/" "$1"
}

update_herdr() {
  local package_nix="$dir/package.nix" repo="herdrdev/herdr" current latest
  current=$(pinned_version "$package_nix")
  latest=$(gh release list --repo "$repo" --exclude-pre-releases --limit 1 --json tagName -q '.[0].tagName' | sed 's/^v//')

  if [[ -z "$latest" ]]; then
    echo "update.sh: could not determine latest stable herdr release" >&2
    exit 1
  fi
  if [[ "$latest" == "$current" ]]; then
    echo "update.sh: herdr already at latest stable version ($current)"
    return
  fi
  echo "update.sh: bumping herdr $current -> $latest"

  local -A asset_names=(
    [x86_64-linux]=herdr-linux-x86_64
    [aarch64-linux]=herdr-linux-aarch64
    [x86_64-darwin]=herdr-macos-x86_64
    [aarch64-darwin]=herdr-macos-aarch64
  )
  local system asset url sha256 sri
  for system in "${!asset_names[@]}"; do
    asset="${asset_names[$system]}"
    url="https://github.com/${repo}/releases/download/v${latest}/${asset}"
    sha256=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null)
    sri=$(nix hash convert --hash-algo sha256 --to sri "$sha256")
    echo "  $system ($asset): $sri"
    set_hash "$package_nix" "$asset" "$sri"
  done
  set_version "$package_nix" "$latest"
}

# update_manifest <package> <component>: herdr-core/core or herdr-app/app.
# The manifest lists each platform's tarball with its sha256, so nothing is
# downloaded here; the builds in `update-check` fetch and check them.
update_manifest() {
  local package="$1" component="$2" nix_file="$dir/$1.nix" manifest current latest
  manifest=$(curl -fsSL "$releases/$component/latest.json") || {
    echo "update.sh: could not fetch $releases/$component/latest.json" >&2
    exit 1
  }
  current=$(pinned_version "$nix_file")
  latest=$(python3 -c 'import json, sys; print(json.load(sys.stdin).get("version", ""))' <<<"$manifest")

  if [[ -z "$latest" ]]; then
    echo "update.sh: could not determine latest $package release" >&2
    exit 1
  fi
  if [[ "$latest" == "$current" ]]; then
    echo "update.sh: $package already at latest version ($current)"
    return
  fi
  echo "update.sh: bumping $package $current -> $latest"

  # Every asset pinned in the .nix file must be in the manifest at this version;
  # check them all before rewriting anything.
  local pairs asset sha256 sri
  pairs=$(python3 - "$manifest" "$package" "$component" "$latest" "$nix_file" <<'PYEOF'
import json, re, sys
manifest, package, component, version, path = sys.argv[1:6]
targets = json.loads(manifest).get("targets", {})
for asset in re.findall(r'name = "(%s-[a-z0-9_-]+)";' % re.escape(package), open(path).read()):
    target = asset.removeprefix(package + "-")
    entry = targets.get(target)
    if not entry:
        sys.exit(f"update.sh: {component} {version} has no {target} build")
    if not entry["url"].endswith(f"/{component}/{version}/{asset}.tar.gz"):
        sys.exit(f"update.sh: unexpected {target} url {entry['url']}")
    print(asset, entry["sha256"])
PYEOF
  )
  while read -r asset sha256; do
    sri=$(nix hash convert --hash-algo sha256 --to sri "$sha256")
    echo "  $asset: $sri"
    set_hash "$nix_file" "$asset" "$sri"
  done <<<"$pairs"
  set_version "$nix_file" "$latest"
}

packages=("$@")
[[ ${#packages[@]} -gt 0 ]] || packages=(herdr herdr-core herdr-app)
for package in "${packages[@]}"; do
  case "$package" in
    herdr) update_herdr ;;
    herdr-core) update_manifest herdr-core core ;;
    herdr-app) update_manifest herdr-app app ;;
    *) echo "update.sh: unknown package $package (herdr, herdr-core, herdr-app)" >&2; exit 2 ;;
  esac
done

echo "update.sh: done. Run 'nix flake check' before committing."
