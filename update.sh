#!/usr/bin/env bash
# Checks the latest stable herdr release (skips `preview-*` pre-releases) and,
# if newer than the pinned version in package.nix, rewrites the version and
# per-platform hashes in place. Run manually, or via the scheduled
# `update-check` GitHub Actions workflow, which opens a PR with the diff.
set -euo pipefail

repo="herdrdev/herdr"
package_nix="$(dirname "$0")/package.nix"

current_version=$(grep -m1 '^  version = ' "$package_nix" | sed -E 's/.*"([^"]+)".*/\1/')

latest_version=$(gh release list --repo "$repo" --exclude-pre-releases --limit 1 --json tagName -q '.[0].tagName' | sed 's/^v//')

if [[ -z "$latest_version" ]]; then
  echo "update.sh: could not determine latest stable herdr release" >&2
  exit 1
fi

if [[ "$latest_version" == "$current_version" ]]; then
  echo "update.sh: already at latest stable version ($current_version)"
  exit 0
fi

echo "update.sh: bumping herdr $current_version -> $latest_version"

declare -A asset_names=(
  [x86_64-linux]=herdr-linux-x86_64
  [aarch64-linux]=herdr-linux-aarch64
  [x86_64-darwin]=herdr-macos-x86_64
  [aarch64-darwin]=herdr-macos-aarch64
)

for system in "${!asset_names[@]}"; do
  asset="${asset_names[$system]}"
  url="https://github.com/${repo}/releases/download/v${latest_version}/${asset}"
  sha256=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null)
  sri=$(nix hash convert --hash-algo sha256 --to sri "$sha256")
  echo "  $system ($asset): $sri"

  # Replace the hash on the line following this system's block, matched by
  # the preceding `name = "<asset>";` line two lines above the hash line.
  python3 - "$package_nix" "$asset" "$sri" <<'PYEOF'
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
done

sed -i -E "s/^(  version = )\"[^\"]+\";/\1\"${latest_version}\";/" "$package_nix"

echo "update.sh: done. Run 'nix flake check' before committing."
