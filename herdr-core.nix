{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.1.20";

  # Map Nix system -> upstream release asset name + content hash.
  # Regenerate with ./update.sh (see README) when bumping `version`.
  assets = {
    x86_64-linux = {
      name = "herdr-core-linux-x86_64";
      hash = "sha256-rGuGiQxFGjdYRiCqpDi3G8DQvUMKLnwdfglfBSxBTnQ=";
    };
    aarch64-linux = {
      name = "herdr-core-linux-aarch64";
      hash = "sha256-XzA3N50VzHbPxy0v0aQmLqHFsk3yeL98/Yrc/3uRSGI=";
    };
    x86_64-darwin = {
      name = "herdr-core-macos-x86_64";
      hash = "sha256-NsAzHD/+oP+q2hlbiaPHSW9/P8W/NeRgXBnITlwgWlY=";
    };
    aarch64-darwin = {
      name = "herdr-core-macos-aarch64";
      hash = "sha256-5YmF0/726QnzPTxaRCbkiYyBVkpVfUY2WRzsnjoGryY=";
    };
  };

  asset =
    assets.${stdenvNoCC.hostPlatform.system}
      or (throw "herdr-nix: no herdr-core release asset for system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "herdr-core";
  inherit version;

  src = fetchurl {
    url = "https://releases.herdr.dev/core/${version}/${asset.name}.tar.gz";
    inherit (asset) hash;
  };

  sourceRoot = ".";

  # The Linux build is static, and hc tells builds apart by their build id; the
  # macOS bundle is signed. Both are installed exactly as released.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 LICENSE THIRD-PARTY-NOTICES -t $out/share/licenses/herdr-core
  ''
  # macOS privacy grants belong to the signed Herdr Core.app, so the commands
  # are links into the bundle, as the upstream installer makes them.
  + (
    if stdenvNoCC.hostPlatform.isDarwin then
      ''
        mkdir -p $out/Applications $out/bin
        cp -R "Herdr Core.app" $out/Applications/
        ln -s "$out/Applications/Herdr Core.app/Contents/MacOS/herdr-core" $out/bin/herdr-core
      ''
    else
      ''
        install -Dm755 herdr-core $out/bin/herdr-core
      ''
  )
  + ''
    ln -s herdr-core $out/bin/hc
    runHook postInstall
  '';

  meta = {
    description = "Persistent terminals and coding agents for Herdr, packaged from official release binaries";
    homepage = "https://github.com/herdrdev/herdr-core";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames assets;
    mainProgram = "hc";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
