#!/usr/bin/env bats
# Exercises update.sh's decision logic and package.nix rewriting by stubbing
# out its network/nix boundary (gh, nix-prefetch-url, nix) on PATH — never
# hits the real GitHub API or Nix store.

setup() {
  TEST_DIR="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME/../update.sh" "$TEST_DIR/update.sh"
  cp "$BATS_TEST_DIRNAME/../package.nix" "$TEST_DIR/package.nix"
  chmod +x "$TEST_DIR/update.sh"

  FAKE_BIN="$TEST_DIR/bin"
  mkdir -p "$FAKE_BIN"
  PATH="$FAKE_BIN:$PATH"

  CURRENT_VERSION=$(grep -m1 '^  version = ' "$TEST_DIR/package.nix" | sed -E 's/.*"([^"]+)".*/\1/')
}

teardown() {
  rm -rf "$TEST_DIR"
}

fake_gh_latest() {
  cat > "$FAKE_BIN/gh" <<EOF
#!/usr/bin/env bash
echo "v$1"
EOF
  chmod +x "$FAKE_BIN/gh"
}

fake_gh_empty() {
  cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo ""
EOF
  chmod +x "$FAKE_BIN/gh"
}

fake_prefetch_tools() {
  cat > "$FAKE_BIN/nix-prefetch-url" <<'EOF'
#!/usr/bin/env bash
echo "0000000000000000000000000000000000000000000000000000"
EOF
  chmod +x "$FAKE_BIN/nix-prefetch-url"

  cat > "$FAKE_BIN/nix" <<'EOF'
#!/usr/bin/env bash
echo "sha256-FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFA0="
EOF
  chmod +x "$FAKE_BIN/nix"
}

@test "already at latest stable version: leaves package.nix untouched, exits 0" {
  fake_gh_latest "$CURRENT_VERSION"

  run bash -c "cd '$TEST_DIR' && ./update.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"already at latest stable version ($CURRENT_VERSION)"* ]]
  diff "$BATS_TEST_DIRNAME/../package.nix" "$TEST_DIR/package.nix"
}

@test "newer stable release: bumps version and all four platform hashes" {
  fake_gh_latest "9.9.9"
  fake_prefetch_tools

  run bash -c "cd '$TEST_DIR' && ./update.sh"

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

  run bash -c "cd '$TEST_DIR' && ./update.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"could not determine latest stable herdr release"* ]]
  diff "$BATS_TEST_DIRNAME/../package.nix" "$TEST_DIR/package.nix"
}
