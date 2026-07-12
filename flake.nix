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
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem =
        { config, pkgs, ... }:
        let
          go = pkgs.go_1_26;
          golangci-lint = pkgs.golangci-lint;

          # Build version = the commit, computed OUTSIDE the hermetic build and
          # injected as a stamp.
          version = inputs.self.shortRev or inputs.self.dirtyShortRev or "unknown";

          # A dev shortcut: run `cmd` natively against the working tree
          devApp = name: runtimeInputs: cmd: {
            type = "app";
            program = pkgs.lib.getExe (
              pkgs.writeShellApplication {
                name = "verseal-${name}";
                inherit runtimeInputs;
                text = ''
                  export GOTOOLCHAIN=local
                  exec ${cmd} "$@"
                '';
              }
            );
          };
        in
        {
          packages.default = (pkgs.buildGoModule.override { inherit go; }) {
            pname = "verseal";
            inherit version;
            src = ./.;

            # No external dependencies yet.
            vendorHash = null;

            # Version injection: stamp the version into the Go binary.
            ldflags = [
              "-X"
              "main.version=${version}"
            ];
          };

          # Formatting, defined once. treefmt-nix exposes it as `nix fmt` and as
          # `checks.treefmt` automatically.
          treefmt = {
            projectRootFile = "flake.nix";
            programs.gofmt.enable = true;
            programs.nixfmt.enable = true;
          };

          pre-commit = {
            check.enable = false;
            settings.hooks = {
              treefmt = {
                enable = true;
                package = config.treefmt.build.wrapper;
              };
              golangci-lint = {
                enable = true;
                package = golangci-lint;
              };
            };
          };

          # Hermetic CI checks (buildGoModule). `checks.treefmt` is added by the
          # treefmt-nix module above.
          checks = {
            build = config.packages.default;

            # `go test ./...` (also runs `go vet`) via buildGoModule's check phase.
            test = config.packages.default.overrideAttrs (_: {
              pname = "verseal-test";
              doCheck = true;
            });

            # Hermetic lint: golangci-lint with the full buildGoModule Go env, so
            # it has the toolchain and (later) the vendored deps to type-check.
            lint = config.packages.default.overrideAttrs (old: {
              pname = "verseal-lint";
              doCheck = true;
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ golangci-lint ];
              checkPhase = ''
                runHook preCheck
                export HOME=$TMPDIR
                export GOLANGCI_LINT_CACHE=$TMPDIR/golangci-lint
                golangci-lint run ./...
                runHook postCheck
              '';
            });
          };

          # System-inferred dev shortcuts: `nix run .#test` / `.#lint`. Format
          # with `nix fmt`; for the CI-identical hermetic runs use `nix flake
          # check`.
          apps = {
            test = devApp "test" [ go ] "go test ./...";
            lint = devApp "lint" [
              go
              golangci-lint
            ] "golangci-lint run";
          };

          devShells.default = pkgs.mkShell {
            # Brings in the pre-commit CLI and hook tools (including golangci-lint),
            # and installs the git pre-commit hook on shell entry.
            inputsFrom = [ config.pre-commit.devShell ];

            packages = [
              go
              pkgs.gopls
              pkgs.gotools
            ];

            # Nix owns the toolchain: never silently download a different Go
            GOTOOLCHAIN = "local";
          };
        };
    };
}
