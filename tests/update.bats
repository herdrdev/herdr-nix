#!/usr/bin/env bats
# Exercises update.sh's decision logic and .nix rewriting by stubbing out its
# network/nix boundary (gh, curl, nix-prefetch-url, nix) on PATH — never hits
# the real GitHub API, releases.herdr.dev or the Nix store.

setup() {
  TEST_DIR="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME/../update.sh" "$TEST_DIR/update.sh"
  cp "$BATS_TEST_DIRNAME"/../{package,herdr-core,herdr-app}.nix "$TEST_DIR/"
  chmod +x "$TEST_DIR/update.sh"

  FAKE_BIN="$TEST_DIR/bin"
  mkdir -p "$FAKE_BIN"
  PATH="$FAKE_BIN:$PATH"

  CURRENT_VERSION=$(grep -m1 '^  version = ' "$TEST_DIR/package.nix" | sed -E 's/.*"([^"]+)".*/\1/')
  CORE_VERSION=$(grep -m1 '^  version = ' "$TEST_DIR/herdr-core.nix" | sed -E 's/.*"([^"]+)".*/\1/')
}

teardown() {
  rm -rf "$TEST_DIR"
}

fake_gh_latest() {
  cat > "$FAKE_BIN/gh" <<EOF
#!$BASH
echo "v$1"
EOF
  chmod +x "$FAKE_BIN/gh"
}

fake_gh_empty() {
  cat > "$FAKE_BIN/gh" <<EOF
#!$BASH
echo ""
EOF
  chmod +x "$FAKE_BIN/gh"
}

fake_prefetch_tools() {
  cat > "$FAKE_BIN/nix-prefetch-url" <<EOF
#!$BASH
echo "0000000000000000000000000000000000000000000000000000"
EOF
  chmod +x "$FAKE_BIN/nix-prefetch-url"

  cat > "$FAKE_BIN/nix" <<EOF
#!$BASH
echo "sha256-FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFA0="
EOF
  chmod +x "$FAKE_BIN/nix"
}

@test "already at latest stable version: leaves package.nix untouched, exits 0" {
  fake_gh_latest "$CURRENT_VERSION"

  run bash -c "cd '$TEST_DIR' && bash ./update.sh herdr"

  [ "$status" -eq 0 ]
  [[ "$output" == *"already at latest stable version ($CURRENT_VERSION)"* ]]
  diff "$BATS_TEST_DIRNAME/../package.nix" "$TEST_DIR/package.nix"
}

@test "newer stable release: bumps version and all four platform hashes" {
  fake_gh_latest "9.9.9"
  fake_prefetch_tools

  run bash -c "cd '$TEST_DIR' && bash ./update.sh herdr"

  [ "$status" -eq 0 ]
  [[ "$output" == *"bumping herdr $CURRENT_VERSION -> 9.9.9"* ]]
  grep -q 'version = "9.9.9";' "$TEST_DIR/package.nix"

  for asset in herdr-linux-x86_64 herdr-linux-aarch64 herdr-macos-x86_64 herdr-macos-aarch64; do
    grep -A1 "name = \"$asset\";" "$TEST_DIR/package.nix" \
      | grep -q 'hash = "sha256-FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFA0=";'
  done
}

@test "gh returns no release: fails with a clear error, leaves package.nix untouched" {
  fake_gh_empty

  run bash -c "cd '$TEST_DIR' && bash ./update.sh herdr"

  [ "$status" -eq 1 ]
  [[ "$output" == *"could not determine latest stable herdr release"* ]]
  diff "$BATS_TEST_DIRNAME/../package.nix" "$TEST_DIR/package.nix"
}

# fake_manifest <version> [targets...]: what releases.herdr.dev/core/latest.json
# serves; with no targets, all four core platforms.
fake_manifest() {
  local version="$1"
  shift
  local targets=("$@") entries="" t
  [ ${#targets[@]} -gt 0 ] || targets=(linux-x86_64 linux-aarch64 macos-x86_64 macos-aarch64)
  for t in "${targets[@]}"; do
    entries+="\"$t\": {\"url\": \"https://releases.herdr.dev/core/$version/herdr-core-$t.tar.gz\", \"sha256\": \"$(printf '%064d' 0)\"},"
  done
  printf '#!%s\necho %q\n' "$BASH" "{\"version\": \"$version\", \"targets\": {${entries%,}}}" > "$FAKE_BIN/curl"
  chmod +x "$FAKE_BIN/curl"
}

@test "herdr-core newer in the manifest: bumps version and all four platform hashes" {
  fake_manifest "9.9.9"
  fake_prefetch_tools

  run bash -c "cd '$TEST_DIR' && bash ./update.sh herdr-core"

  [ "$status" -eq 0 ]
  [[ "$output" == *"bumping herdr-core $CORE_VERSION -> 9.9.9"* ]]
  grep -q 'version = "9.9.9";' "$TEST_DIR/herdr-core.nix"
  for asset in herdr-core-linux-x86_64 herdr-core-linux-aarch64 herdr-core-macos-x86_64 herdr-core-macos-aarch64; do
    grep -A1 "name = \"$asset\";" "$TEST_DIR/herdr-core.nix" \
      | grep -q 'hash = "sha256-FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFA0=";'
  done
}

@test "herdr-core already current: leaves herdr-core.nix untouched" {
  fake_manifest "$CORE_VERSION"

  run bash -c "cd '$TEST_DIR' && bash ./update.sh herdr-core"

  [ "$status" -eq 0 ]
  [[ "$output" == *"herdr-core already at latest version ($CORE_VERSION)"* ]]
  diff "$BATS_TEST_DIRNAME/../herdr-core.nix" "$TEST_DIR/herdr-core.nix"
}

@test "manifest missing a pinned platform: fails before rewriting anything" {
  fake_manifest "9.9.9" linux-x86_64 linux-aarch64 macos-aarch64
  fake_prefetch_tools

  run bash -c "cd '$TEST_DIR' && bash ./update.sh herdr-core"

  [ "$status" -ne 0 ]
  [[ "$output" == *"has no macos-x86_64 build"* ]]
  diff "$BATS_TEST_DIRNAME/../herdr-core.nix" "$TEST_DIR/herdr-core.nix"
}
