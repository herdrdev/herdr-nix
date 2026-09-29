{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  stdenv,
}:

let
  version = "0.9.2";

  # Map Nix system -> upstream release asset name + content hash.
  # Regenerate with ./update.sh (see README) when bumping `version`.
  assets = {
    x86_64-linux = {
      name = "herdr-linux-x86_64";
      hash = "sha256-dN40dG+WI2921Zn49dJDn4hDUeq+JbdJXg7at1QUBko=";
    };
    aarch64-linux = {
      name = "herdr-linux-aarch64";
      hash = "sha256-ULpv6N3l/zWvZlQILX4aSvy1jJ/z0iv8+dQURclx/Mc=";
    };
    x86_64-darwin = {
      name = "herdr-macos-x86_64";
      hash = "sha256-Zlt/eu6Wv900/0bBEVmRcM7uaNhgyf6eoXzV+agL3EM=";
    };
    aarch64-darwin = {
      name = "herdr-macos-aarch64";
      hash = "sha256-5drpx9kwEJaIl94QxunqKqyxSWX3ueOz0GHbqC0qGUQ=";
    };
  };

  asset =
    assets.${stdenvNoCC.hostPlatform.system}
      or (throw "herdr-nix: no release asset for system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "herdr";
  inherit version;

  src = fetchurl {
    url = "https://github.com/herdrdev/herdr/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };

  dontUnpack = true;
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';

  meta = {
    description = "Terminal-native agent runtime packaged from official release binaries";
    homepage = "https://github.com/herdrdev/herdr";
    # herdr itself is dual-licensed; the open-source track is AGPL-3.0-or-later.
    # This packaging repo's own code is MIT (see LICENSE) — see README for the distinction.
    license = lib.licenses.agpl3Plus;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "herdr";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
