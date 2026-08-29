{
  lib,
  stdenv,
  callPackage,
  electron_41,
  nodejs_24,
  pnpm,
  pnpmConfigHook,
  makeWrapper,
  writableTmpDirAsHomeHook,
  copyDesktopItems,
  makeDesktopItem,
  autoPatchelfHook,
}:

let
  electron = electron_41;
in

stdenv.mkDerivation (finalAttrs: {
  pname = "t3code";
  version = "0.0.36";

  src = callPackage ./source.nix { };

  pnpmDeps = callPackage ./pnpm-deps.nix {
    src = finalAttrs.src;
    inherit pnpm;
  };

  nativeBuildInputs = [
    nodejs_24
    pnpm
    pnpmConfigHook
    makeWrapper
    writableTmpDirAsHomeHook
    copyDesktopItems
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib
  ];

  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-*.so.*"
  ];

  strictDeps = true;

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    T3CODE_DESKTOP_VERSION = finalAttrs.version;
  };

  desktopItems = [
    (makeDesktopItem {
      name = "t3code";
      desktopName = "T3 Code";
      comment = "Desktop control surface for local coding agents";
      exec = "t3code --no-sandbox %U";
      tryExec = "t3code";
      terminal = false;
      icon = "t3code";
      startupWMClass = "t3code";
      categories = [ "Development" ];
      mimeTypes = [ "x-scheme-handler/t3code" ];
    })
  ];

  buildPhase = ''
    runHook preBuild

    cp -r "${electron.dist}" $HOME/.electron-dist
    chmod -R u+w $HOME/.electron-dist

    export PATH="$PWD/node_modules/.bin:$PATH"
    export npm_config_nodedir="${electron.headers}"
    export npm_config_offline=true
    export npm_config_prefer_offline=true

    node scripts/build-desktop-artifact.ts --platform linux --target dir --arch x64

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    unpacked=$(find . -type d -name 'linux*-unpacked' | head -n1)
    if [ -z "$unpacked" ]; then
      echo "no linux-unpacked output found" >&2
      exit 1
    fi

    mkdir -p $out/share/t3code
    cp -r "$unpacked"/. $out/share/t3code/

    makeWrapper ${lib.getExe electron} $out/bin/t3code \
      --inherit-argv0 \
      --add-flags $out/share/t3code/resources/app.asar \
      --add-flags "''${NIXOS_OZONE_WL:+''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3}}"

    runHook postInstall
  '';

  meta = {
    description = "Desktop control surface for local coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    mainProgram = "t3code";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.mit;
  };
})
