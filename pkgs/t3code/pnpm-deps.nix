{
  fetchPnpmDeps,
  pnpm,
  src,
}:

fetchPnpmDeps {
  pname = "t3code";
  version = "0.0.36";
  inherit src;
  inherit pnpm;
  fetcherVersion = 4;
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
}
