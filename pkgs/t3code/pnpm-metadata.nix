{
  lib,
  stdenvNoCC,
  cacert,
  nodejs_24,
  pnpm,
  writableTmpDirAsHomeHook,
  src,
}:

# Resolves the workspace dependencies (networked, fixed-output) solely to
# populate pnpm 11's registry metadata cache ("package mirror"). The
# build-desktop-artifact.ts stage install runs `vp install --prod` in a
# generated stage without a lockfile; offline resolution in the sandbox needs
# this metadata cache on top of the fetchPnpmDeps tarball store.
stdenvNoCC.mkDerivation {
  name = "t3code-pnpm-metadata";
  inherit src;

  nativeBuildInputs = [
    cacert
    nodejs_24
    pnpm
    writableTmpDirAsHomeHook
  ];

  impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  env.NPM_CONFIG_MANAGE_PACKAGE_MANAGER_VERSIONS = "true";

  dontConfigure = true;

  buildPhase = ''
    # Force a fresh resolution pass so every registry packument is fetched
    # into the metadata cache. pnpm delegates to the workspace's managed
    # pnpm 11.10 (the same one the stage install uses), so the cache format
    # matches exactly.
    rm pnpm-lock.yaml
    pnpm install --ignore-scripts --lockfile-only

    mkdir $out
    # Contains "which version a range resolved to" state from this online
    # run; the offline stage resolution must not reuse it.
    rm -f "$HOME/.cache/pnpm/lockfile-verified.jsonl"
    cp -r "$HOME/.cache/pnpm" $out/pnpm-cache
  '';

  installPhase = ''
    runHook preInstall
    runHook postInstall
  '';

  outputHashAlgo = "sha256";
  outputHash = "sha256-AyuD6KVICQqSCtEY8EvX6OQhpzmdMWdutWoGawswfMM=";
  outputHashMode = "recursive";
}
