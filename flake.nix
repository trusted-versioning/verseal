{
  description = "verseal: sealed versioning. Deterministic version computation bound to a signed integrity ledger.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Where the flake evaluates (dev shell, native builds), NOT which artifacts
      # exist: verseal-darwin-amd64 is cross-compiled from linux. x86_64-darwin
      # was dropped as a host by nixpkgs 26.11.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        ./nix/toolchain.nix # go pin, filtered sources, deps proxy, command vocabulary
        ./nix/tasks.nix # the task graph: packages, checks, apps
        ./nix/dev.nix # formatting, pre-commit hook, dev shell
      ];
    };
}
