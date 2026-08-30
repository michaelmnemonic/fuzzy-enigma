# t3code-nix-ng

> **⚠️ Warning: Slop repository.** The content here is mostly LLM-generated, unreviewed, and not intended for production use.

## What is this?

A Nix flake that packages [T3 Code](https://github.com/pingdotgg/t3code) (a desktop control surface for local coding agents) for **x86_64-linux**.

## Contents

- `flake.nix` – Flake definition, exposes `packages.t3code` (and `default`)
- `pkgs/t3code/default.nix` – Derivation: builds the Electron app offline from source (pnpm + cargo), sets up wrapper, desktop entry, and icons
- `pkgs/t3code/source.nix` – Source fetch from GitHub
- `pkgs/t3code/pnpm-deps.nix` / `pnpm-metadata.nix` – Offline dependency store and registry metadata cache

## Usage (at your own risk)

```sh
nix run .#t3code
```

Launches with `--no-sandbox`. x86_64-linux only.
