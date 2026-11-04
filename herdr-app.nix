{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeDesktopItem,
  copyDesktopItems,
  libxcb,
  libxkbcommon,
  libGL,
  vulkan-loader,
  wayland,
}:

let
  version = "0.1.13";

  # Map Nix system -> upstream release asset name + content hash.
  # Regenerate with ./update.sh (see README) when bumping `version`.
  assets = {
    x86_64-linux = {
      name = "herdr-app-linux-x86_64";
      hash = "sha256-d7C+cqRsoUuzZzZaBBZGQfkUs6aXErrDkdOcVqlZvvQ=";
    };
    aarch64-linux = {
      name = "herdr-app-linux-aarch64";
      hash = "sha256-LluwXEfP+60BitNCF+pMgWR21+uEJpL3QHmMkCDwKB4=";
    };
    aarch64-darwin = {
      name = "herdr-app-macos-aarch64";
      hash = "sha256-9d0LyBqp72HPv7bvn9v0/n9mTU7Gdu4NyI8TzJdZ0NA=";
    };
  };

  asset =
    assets.${stdenvNoCC.hostPlatform.system}
      or (throw "herdr-nix: no herdr-app release asset for system ${stdenvNoCC.hostPlatform.system}");
  isLinux = stdenvNoCC.hostPlatform.isLinux;
in
stdenvNoCC.mkDerivation {
  pname = "herdr-app";
  inherit version;

  src = fetchurl {
    url = "https://releases.herdr.dev/app/${version}/${asset.name}.tar.gz";
    inherit (asset) hash;
  };

  sourceRoot = ".";

  nativeBuildInputs = lib.optionals isLinux [
    autoPatchelfHook
    copyDesktopItems
  ];
  buildInputs = lib.optionals isLinux [
    stdenv.cc.cc.lib
    libxcb
    libxkbcommon
  ];
  # wgpu and the Wayland backend load these with dlopen. They go on the RUNPATH,
  # not LD_LIBRARY_PATH: the app starts herdr-core, which passes its environment
  # on to every terminal.
  runtimeDependencies = lib.optionals isLinux [
    libGL
    vulkan-loader
    wayland
  ];

  # The macOS bundle is signed; keep it byte for byte.
  dontFixup = !isLinux;

  desktopItems = lib.optionals isLinux [
    (makeDesktopItem {
      name = "herdr-app";
      desktopName = "Herdr";
      comment = "Terminals and coding agents that keep running";
      exec = "herdr-app";
      icon = "herdr-app";
      terminal = false;
      categories = [ "Development" ];
      startupWMClass = "herdr-app";
    })
  ];

  # The app updates itself only where it finds its release folder (the binary
  # next to herdr-app.svg) or a Herdr.app bundle, so on Linux the icon goes to
  # the icon theme instead. A bundle in /nix/store is left alone once
  # herdrdev/herdr-app#459 lands.
  installPhase = ''
    runHook preInstall
  ''
  + (
    if isLinux then
      ''
        install -Dm755 herdr-app/herdr-app $out/bin/herdr-app
        install -Dm644 herdr-app/herdr-app.svg $out/share/icons/hicolor/scalable/apps/herdr-app.svg
        install -Dm644 herdr-app/LICENSE herdr-app/THIRD-PARTY-NOTICES -t $out/share/licenses/herdr-app
      ''
    else
      ''
        mkdir -p $out/Applications $out/bin
        cp -R Herdr.app $out/Applications/
        ln -s $out/Applications/Herdr.app/Contents/MacOS/Herdr $out/bin/herdr-app
      ''
  )
  + ''
    runHook postInstall
  '';

  meta = {
    description = "Herdr desktop app, packaged from official release binaries";
    homepage = "https://github.com/herdrdev/herdr-app";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames assets;
    mainProgram = "herdr-app";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
