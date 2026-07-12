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

          # Shared offline Go env for the build and checks.
          goEnv = ''
            export HOME=$TMPDIR GOCACHE=$TMPDIR/go-build GOPATH=$TMPDIR/go
            export GOFLAGS=-mod=mod GOPROXY=off
          '';

          # Tool commands, defined once so the check and the app can't drift.
          testCmd =
            race:
            "go test${pkgs.lib.optionalString race " -race"} -covermode=atomic -coverprofile=cover.out ./...";
          lintCmd = "golangci-lint run ./...";

          # NON-STANDARD: idiomatic Nix builds each arch on its own native runner; we cross
          # from one runner until native runners exist. First dep -> vendor from
          # `(buildGoModule { inherit pname version src; vendorHash; }).goModules`
          crossBuild =
            goos: goarch:
            pkgs.stdenvNoCC.mkDerivation {
              pname = "verseal-${goos}-${goarch}";
              inherit version;
              src = ./.;
              nativeBuildInputs = [ go ];
              dontFixup = true; # static, stripped, -trimpath binary needs no fixup (silences patchelf)
              buildPhase = ''
                runHook preBuild
                ${goEnv}
                export CGO_ENABLED=0 GOOS=${goos} GOARCH=${goarch}
                go build -trimpath -ldflags "-s -w -buildid= -X main.version=${version}" -o verseal .
                runHook postBuild
              '';
              installPhase = ''
                runHook preInstall
                install -Dm755 verseal $out/bin/verseal
                runHook postInstall
              '';
              meta.mainProgram = "verseal";
            };

          # race + coverage. gocover-cobertura needs go + the source (both here), so the
          # Cobertura conversion happens in this derivation.
          testRun = pkgs.stdenv.mkDerivation {
            name = "verseal-test";
            src = ./.;
            nativeBuildInputs = [
              go
              pkgs.gocover-cobertura
            ];
            buildPhase = ''
              ${goEnv}
              export CGO_ENABLED=1
              ${testCmd true}
            '';
            # patch: timestamp 0 (deterministic) + repo-root source (sandbox path breaks the
            # GitHub file mapping).
            installPhase = ''
              mkdir -p $out
              gocover-cobertura < cover.out \
                | sed -e 's/timestamp="[0-9]*"/timestamp="0"/' \
                      -e 's#<source>[^<]*</source>#<source>.</source>#' \
                > $out/coverage.xml
            '';
          };
        in
        {
          packages = {
            # default = the current system; every arch goes through crossBuild.
            default = crossBuild go.GOOS go.GOARCH;
            verseal-linux-amd64 = crossBuild "linux" "amd64";
            verseal-linux-arm64 = crossBuild "linux" "arm64";
            verseal-darwin-amd64 = crossBuild "darwin" "amd64";
            verseal-darwin-arm64 = crossBuild "darwin" "arm64";

            # cobertura xml from the test run, for the github code quality upload.
            coverage = pkgs.runCommand "verseal-coverage" { } ''
              mkdir -p $out
              cp ${testRun}/coverage.xml $out/coverage.xml
            '';
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

          # Hermetic CI checks. `checks.treefmt` is added by the treefmt-nix module.
          checks = {
            build = config.packages.default;

            test = testRun;

            lint = pkgs.stdenvNoCC.mkDerivation {
              name = "verseal-lint";
              src = ./.;
              nativeBuildInputs = [
                go
                golangci-lint
              ];
              buildPhase = ''
                ${goEnv}
                export GOLANGCI_LINT_CACHE=$TMPDIR/golangci-lint
                ${lintCmd}
              '';
              installPhase = "touch $out";
            };
          };

          # Dev shortcuts (`nix run`). CI-identical hermetic runs = `nix flake check`.
          # These run against the local working tree, day to day development.
          apps = {
            # race by default (needs CGO -> stdenv.cc); `.#test:sync` skips it for speed.
            test = devApp "test" [
              go
              pkgs.stdenv.cc
            ] (testCmd true);
            "test:sync" = devApp "test-sync" [ go ] (testCmd false);
            lint = devApp "lint" [
              go
              golangci-lint
            ] lintCmd;
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
