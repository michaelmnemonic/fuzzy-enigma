{
  lib,
  stdenv,
  callPackage,
  cacert,
  electron_41,
  fetchurl,
  nodejs_24,
  pnpm,
  pnpmConfigHook,
  makeWrapper,
  writableTmpDirAsHomeHook,
  copyDesktopItems,
  makeDesktopItem,
  gh,
  imagemagick,
  python3,
  rustPlatform,
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

  # Registry metadata cache for the offline stage install (see file header).
  pnpmMetadata = callPackage ./pnpm-metadata.nix {
    src = finalAttrs.src;
  };

  # vp manages the package manager version from `packageManager` and would
  # download it at build time; seed its cache instead.
  pnpmTarball = fetchurl {
    url = "https://registry.npmjs.org/pnpm/-/pnpm-11.10.0.tgz";
    hash = "sha256-YgtmBepPYvxWptCphzP0eQcdAyHgPkhrUix+mnRhdDE=";
  };

  nativeBuildInputs = [
    cacert
    nodejs_24
    pnpm
    pnpmConfigHook
    makeWrapper
    writableTmpDirAsHomeHook
    copyDesktopItems
    imagemagick
    python3
    rustPlatform.cargoSetupHook
    rustPlatform.rust.cargo
    rustPlatform.rust.rustc
  ];

  # No autoPatchelfHook: the unpacked dist ships its own Electron binary, but
  # it is never run — the wrapper below launches nixpkgs' electron, which
  # already provides the full GUI dependency set. Patching the shipped binary
  # would only drag gtk3/cups/dbus/... into the closure for nothing.
  strictDeps = true;

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) pname version;
    src = finalAttrs.src;
    sourceRoot = "${finalAttrs.src.name}/native/resource-monitor";
    hash = "sha256-5cmG2daM1bVOA23gjjoalbx0fEL1hmqV6WZov0sUZp8=";
  };

  cargoRoot = "native/resource-monitor";

  # Patch the desktop artifact builder so the stage install resolves fully
  # offline: the stage's generated pnpm-workspace.yaml gains the store dir
  # (prepopulated by pnpmDeps) and pnpm's offline/mirror settings, and
  # electron-builder is pointed at a local Electron dist instead of
  # downloading one from github.com. vp spawns the managed pnpm in a way
  # that ignores the ambient npm_config_* env, hence the file patches.
  postPatch = ''
python3 <<'PYEOF'
from pathlib import Path

p = Path("scripts/build-desktop-artifact.ts")
s = p.read_text()

old = """    path.join(stageAppDir, "pnpm-workspace.yaml"),
    stageWorkspaceConfigString,
  );"""
new = """    path.join(stageAppDir, "pnpm-workspace.yaml"),
    stageWorkspaceConfigString +
      "\\noffline: true\\nprefer-offline: true\\nstore-dir: " +
      (process.env.T3CODE_PNPM_STORE_DIR ?? "") +
      "\\n",
  );"""
n = s.count(old)
assert n == 1, f"patch pattern count: {n}"
s = s.replace(old, new)

old = """    "electron-builder",
    "--projectDir",
    stageAppDir,"""
new = """    "electron-builder",
    ...(process.env.T3CODE_ELECTRON_DIST
      ? ["--config.electronDist=" + process.env.T3CODE_ELECTRON_DIST]
      : []),
    "--projectDir",
    stageAppDir,"""
n = s.count(old)
assert n == 1, f"patch pattern count: {n}"
s = s.replace(old, new)

p.write_text(s)
PYEOF
  '';

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
    export T3CODE_ELECTRON_DIST="$HOME/.electron-dist"

    export PATH="$PWD/node_modules/.bin:$PATH"
    export npm_config_nodedir="${electron.headers}"
    export npm_config_offline=true
    export npm_config_prefer_offline=true

    # Pre-populate the pnpm registry metadata mirror so the stage install can
    # resolve offline (the stage has no lockfile). Generated with the same
    # managed pnpm version the stage uses, so the cache format matches.
    mkdir -p "$HOME/.cache"
    cp -r "${finalAttrs.pnpmMetadata}/pnpm-cache" "$HOME/.cache/pnpm"
    chmod -R u+w "$HOME/.cache/pnpm"

    # The stage re-resolves dependency ranges and would pick versions newer
    # than the workspace lockfile, whose tarballs are not in the offline
    # store. Filter every cached packument down to the lockfile's versions so
    # offline resolution can only choose tarballs that exist in the store.
python3 <<'PYEOF'
import json, glob, os

lock_versions = set()
section = None
for line in open("pnpm-lock.yaml"):
    if line.startswith("packages:"):
        section = "packages"
        continue
    if line.startswith("snapshots:"):
        section = "snapshots"
        continue
    if section != "packages" or not line.startswith("  "):
        continue
    key = line.strip()
    if key.endswith(":"):
        key = key[:-1]
    if key.startswith("'") and key.endswith("'"):
        key = key[1:-1]
    if key.startswith("/"):
        key = key[1:]
    if "(" in key:
        key = key.split("(", 1)[0]
    name, _, version = key.rpartition("@")
    if name and version:
        lock_versions.add(f"{name}@{version}")

n_files, n_filtered = 0, 0
# "**/" on both sides: scoped packages live in a subdirectory per scope
# (.../registry.npmjs.org/@scope/name.jsonl).
for path in glob.glob(os.environ["HOME"] + "/.cache/pnpm/v11/**/registry.npmjs.org/**/*.jsonl", recursive=True):
    n_files += 1
    # Cached packument lines do not reliably carry a "name" field, so derive
    # the package name from the cache layout, which mirrors the registry path.
    path_name = path.split("registry.npmjs.org/", 1)[-1]
    if path_name.endswith(".jsonl"):
        path_name = path_name[: -len(".jsonl")]
    out_lines = []
    changed = False
    for line in open(path):
        stripped = line.strip()
        if not stripped:
            continue
        try:
            obj = json.loads(stripped)
        except json.JSONDecodeError:
            out_lines.append(line)
            continue
        versions = obj.get("versions")
        name = obj.get("name") or path_name
        if isinstance(versions, dict) and name:
            keep = {v: d for v, d in versions.items() if f"{name}@{v}" in lock_versions}
            if len(keep) != len(versions):
                changed = True
                n_filtered += 1
            obj["versions"] = keep
            obj["dist-tags"] = {}
            out_lines.append(json.dumps(obj, separators=(",", ":")) + "\n")
        else:
            out_lines.append(line)
    open(path, "w").writelines(out_lines)
print(f"pnpm mirror filter: {n_files} files, {n_filtered} packuments filtered")
PYEOF

    # The stage's vp-managed pnpm is spawned with a sanitized environment, so
    # persist the offline settings in pnpm's config files instead.
    for rc in "$HOME/.npmrc" "$HOME/.config/pnpm/rc"; do
      mkdir -p "$(dirname "$rc")"
      {
        echo "offline=true"
        echo "prefer-offline=true"
        echo "store-dir=$STORE_PATH"
      } >> "$rc"
    done
    export T3CODE_PNPM_STORE_DIR="$STORE_PATH"

    # Seed vp's managed package-manager cache so `vp install` in the stage
    # does not try to download pnpm from the registry. vp 0.2.x uses the
    # monolithic ~/.vite-plus root (HOME is $TMPDIR in the build).
    mkdir -p "$HOME/.vite-plus/package_manager/pnpm/11.10.0"
    tar -xzf ${finalAttrs.pnpmTarball} -C "$HOME/.vite-plus/package_manager/pnpm/11.10.0"
    mv "$HOME/.vite-plus/package_manager/pnpm/11.10.0/package" \
       "$HOME/.vite-plus/package_manager/pnpm/11.10.0/pnpm"
    touch "$HOME/.vite-plus/package_manager/pnpm/11.10.0.lock"
    # vp normally writes these unix shims itself after downloading; the
    # tarball only ships .cjs/.mjs entry points.
    for name in pnpm pnpx; do
      cat > "$HOME/.vite-plus/package_manager/pnpm/11.10.0/pnpm/bin/$name" <<'EOF'
#!/bin/sh
basedir=$(dirname "$(echo "$0" | sed -e 's,\\,/,g')")

case `uname` in
    *CYGWIN*|*MINGW*|*MSYS*)
        if command -v cygpath > /dev/null 2>&1; then
            basedir=`cygpath -w "$basedir"`
        fi
    ;;
esac

if [ -x "$basedir/node" ]; then
    exec "$basedir/node" "$basedir/__SHIM_NAME__.cjs" "$@"
else
    exec node "$basedir/__SHIM_NAME__.cjs" "$@"
fi
EOF
      sed -i "s/__SHIM_NAME__/$name/" "$HOME/.vite-plus/package_manager/pnpm/11.10.0/pnpm/bin/$name"
      chmod +x "$HOME/.vite-plus/package_manager/pnpm/11.10.0/pnpm/bin/$name"
    done

    # The pnpm tarball ships scripts with `#!/usr/bin/env ...` shebangs, which
    # cannot resolve inside the Nix sandbox (no /usr/bin). pnpm's bundled
    # node-gyp shim runs during the stage install's native rebuilds (node-pty).
    patchShebangs "$HOME/.vite-plus/package_manager/pnpm/11.10.0/pnpm"

    # --keep-stage: the script only copies file artifacts (e.g. AppImage) from
    # the stage's dist/ to the output dir; the linux-unpacked directory we
    # install from would be deleted with the stage otherwise.
    node scripts/build-desktop-artifact.ts --platform linux --target dir --arch x64 --keep-stage

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Lives inside the kept stage dir, not the source tree (see --keep-stage).
    unpacked=$(find "''${NIX_BUILD_TOP:-.}" -type d -name 'linux*-unpacked' | head -n1)
    if [ -z "$unpacked" ]; then
      echo "no linux-unpacked output found" >&2
      exit 1
    fi

    mkdir -p $out/share/t3code
    cp -r "$unpacked"/. $out/share/t3code/

    # The shipped chrome-sandbox helper is not setuid inside the Nix store
    # (setuid bits cannot survive there), and the sandbox-enabled startup
    # path CHECK-traps with SIGILL even with it removed (this is the
    # standard NixOS Electron tradeoff). Launch with the Chromium sandbox
    # disabled, matching the desktop entry.
    rm -f $out/share/t3code/chrome-sandbox

    # Launch the shipped Electron binary (electron-builder renamed it to
    # `t3code`). Electron derives `app.isPackaged` from the executable's base
    # name, so running nixpkgs' `electron` directly put the app in dev mode:
    # the backend was then spawned with cwd = <app.asar>, which fails its
    # preflight fs.access. The shipped binary sits next to
    # resources/app.asar (loaded automatically) and its RPATHs already point
    # at the patched nixpkgs electron dependencies.
    makeWrapper $out/share/t3code/t3code $out/bin/t3code \
      --add-flags "--no-sandbox" \
      --suffix PATH : ${lib.makeBinPath [ gh ]} \
      --add-flags "''${NIXOS_OZONE_WL:+''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3}}"

    # App icon for the desktop entry; upstream ships a single 1024x1024 PNG.
    for size in 16 24 32 48 64 128 256; do
      dir=$out/share/icons/hicolor/''${size}x''${size}/apps
      mkdir -p "$dir"
      magick "apps/marketing/public/icon.png" -resize "''${size}x''${size}" "$dir/t3code.png"
    done

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
