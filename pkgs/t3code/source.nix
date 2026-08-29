{
  lib,
  fetchFromGitHub,
}:

fetchFromGitHub {
  owner = "pingdotgg";
  repo = "t3code";
  rev = "v0.0.36";
  hash = lib.fakeHash;
}
