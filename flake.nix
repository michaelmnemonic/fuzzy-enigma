{
  description = "T3 Code - desktop control surface for local coding agents";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    packages = nixpkgs.lib.genAttrs [ "x86_64-linux" ] (system: rec {
      t3code = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/t3code { };
      default = t3code;
    });
  };
}

