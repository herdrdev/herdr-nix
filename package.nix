{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  stdenv,
}:

let
  version = "0.7.3";

  # Map Nix system -> upstream release asset name + content hash.
  # Regenerate with ./update.sh (see README) when bumping `version`.
  assets = {
    x86_64-linux = {
      name = "herdr-linux-x86_64";
      hash = "sha256-BD70Psur2ihGXc/x7sMYRRgVDVZ7i48gzanGyIdwZB0=";
    };
    aarch64-linux = {
      name = "herdr-linux-aarch64";
      hash = "sha256-6kkAlPLHw5CZhwhX0Axkxijve166GWffQlgDNFXuLLE=";
    };
    x86_64-darwin = {
      name = "herdr-macos-x86_64";
      hash = "sha256-m1810oOwh37toM9muh7x2VrkDzLoWKBNoAQfOiDfAnw=";
    };
    aarch64-darwin = {
      name = "herdr-macos-aarch64";
      hash = "sha256-sxNFOS0ATsHxssgh4a1gEBn6g4X+HkxpMTIetYqSB3M=";
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
    url = "https://github.com/ogulcancelik/herdr/releases/download/v${version}/${asset.name}";
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
    description = "Terminal-native agent multiplexer (unofficial packaging, prebuilt upstream release binary)";
    homepage = "https://github.com/ogulcancelik/herdr";
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
