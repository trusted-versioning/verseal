# The task graph. One buildGoModule `base` node owns all builder mechanics
# (module proxy, source setup, go invocation); every task is a declarative
# variant of it. The deps proxy is a single shared node, pinned to
# go.mod/go.sum so only a dependency change refetches it.
#
#   go.mod + go.sum ──> deps proxy
#                           │
#   Go files (goSrc) ──> base ─┬─> packages.default            native, unit tests certify it
#                              ├─> packages.verseal-<os>-<a>   cross variants ──> packages.dist
#                              ├─> checks.test                 coverage variant = packages.coverage
#                              ├─> checks."test:e2e"
#                              └─> checks.lint                 (+ .golangci.yml via lintSrc)
#   Go files only ──> checks.test-tags                         tier-tag guard
#   packages.default ──> checks.build
#
# `nix build .#<package>` builds a package node, `nix flake check` runs every
# check node, `nix run .#<app>` runs a task against the working tree.
{
  perSystem =
    {
      pkgs,
      config,
      toolkit,
      ...
    }:
    let
      inherit (toolkit)
        go
        golangci-lint
        version
        depsSrc
        goSrc
        lintSrc
        testCmd
        lintCmd
        ;

      base = (pkgs.buildGoModule.override { inherit go; }) {
        pname = "verseal";
        inherit version;
        src = goSrc;
        vendorHash = "sha256-hQP6bDIZb1A2ZXZj/osi0pNXns6a9MR4tZBeRSPXjyY=";
        # proxyVendor (go mod download, not go mod vendor) because test files
        # carry build tags: `go mod vendor` prunes tag-gated test deps
        # (testify), a proxy cache does not.
        proxyVendor = true;
        # Pin the deps node to go.mod/go.sum with a static name: it must not
        # rebuild when code or the commit changes, and every variant must share
        # it. vendorHash churns only with the deps (re-pin via fakeHash).
        overrideModAttrs = _: _: {
          name = "verseal-deps-go-modules";
          src = depsSrc;
        };
        ldflags = [
          "-s"
          "-w"
          "-X main.version=${version}"
        ];
        # The native artifact is certified by its unit tests (nixpkgs doCheck
        # convention). Richer gates (race, integration, e2e) are check nodes.
        checkFlags = [ "-tags=unit" ];
        meta.mainProgram = "verseal";
      };

      # NON-STANDARD: idiomatic Nix builds each arch on its own native runner;
      # we cross with Go's own compiler from one runner until native runners
      # exist. Foreign binaries cannot run their tests here, hence
      # doCheck = false.
      cross =
        goos: goarch:
        base.overrideAttrs (previous: {
          pname = "verseal-${goos}-${goarch}";
          env = previous.env // {
            GOOS = goos;
            GOARCH = goarch;
            CGO_ENABLED = "0";
          };
          doCheck = false;
          # A native-stdenv cross build installs to bin/<goos>_<goarch>/.
          postInstall = ''
            if [ -d $out/bin/${goos}_${goarch} ]; then
              mv $out/bin/${goos}_${goarch}/* $out/bin/
              rmdir $out/bin/${goos}_${goarch}
            fi
          '';
        });

      # A test variant replaces the whole checkPhase: the default runs go test
      # per package dir, which would overwrite a single coverage profile.
      # version and ldflags are cleared so the commit stamp does not invalidate
      # check nodes (only code and deps changes rerun them).
      check =
        name: script:
        base.overrideAttrs {
          pname = name;
          version = "0";
          __intentionallyOverridingVersion = true;
          ldflags = [ ];
          dontBuild = true;
          doCheck = true;
          checkPhase = ''
            runHook preCheck
            ${script}
            runHook postCheck
          '';
          installPhase = "touch $out";
        };

      # unit+integration gate AND the coverage source: one combined-tags run
      # compiles both tiers, so coverage spans both with no profile merge. e2e
      # is excluded (subprocess coverage is a separate mechanism). Cobertura
      # output is patched for determinism: timestamp zeroed, sandbox path
      # replaced (it breaks the GitHub file mapping).
      testRun = (check "verseal-test" (testCmd "unit,integration" true)).overrideAttrs (previous: {
        nativeBuildInputs = previous.nativeBuildInputs ++ [ pkgs.gocover-cobertura ];
        installPhase = ''
          mkdir -p $out
          gocover-cobertura < cover.out \
            | sed -e 's/timestamp="[0-9]*"/timestamp="0"/' \
                  -e 's#<source>[^<]*</source>#<source>.</source>#' \
            > $out/coverage.xml
        '';
      });

      # A dev shortcut: run `cmd` natively against the working tree.
      devApp = name: runtimeInputs: cmd: {
        type = "app";
        meta.description = cmd;
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

      # Race needs CGO, hence a C compiler; race-free runs need only go.
      testApp =
        name: tags: race:
        devApp name ([ go ] ++ pkgs.lib.optional race pkgs.stdenv.cc) (testCmd tags race);
    in
    {
      packages = {
        # default = the current system; other arches are cross variants.
        default = base;
        verseal-linux-amd64 = cross "linux" "amd64";
        verseal-linux-arm64 = cross "linux" "arm64";
        verseal-darwin-amd64 = cross "darwin" "amd64";
        verseal-darwin-arm64 = cross "darwin" "arm64";

        # Every release artifact under one output, named for distribution:
        # `nix build .#dist` -> result/verseal-<os>-<arch>.
        dist = pkgs.runCommand "verseal-dist-${version}" { } ''
          mkdir -p $out
          install -Dm755 ${config.packages.verseal-linux-amd64}/bin/verseal $out/verseal-linux-amd64
          install -Dm755 ${config.packages.verseal-linux-arm64}/bin/verseal $out/verseal-linux-arm64
          install -Dm755 ${config.packages.verseal-darwin-amd64}/bin/verseal $out/verseal-darwin-amd64
          install -Dm755 ${config.packages.verseal-darwin-arm64}/bin/verseal $out/verseal-darwin-arm64
        '';

        # cobertura xml (unit + integration) for the github code quality upload.
        coverage = testRun;
      };

      # Hermetic CI gates. `checks.treefmt` is added by the treefmt-nix module.
      checks = {
        build = config.packages.default;

        test = testRun;

        # e2e drives the built binary as a subprocess: slower, not in the
        # coverage number, so a separate node.
        "test:e2e" = check "verseal-test-e2e" (testCmd "e2e" false);

        lint = (check "verseal-lint" lintCmd).overrideAttrs (previous: {
          src = lintSrc; # + .golangci.yml
          nativeBuildInputs = previous.nativeBuildInputs ++ [ golangci-lint ];
          preCheck = ''
            export GOLANGCI_LINT_CACHE=$TMPDIR/golangci-lint
          '';
        });

        # Every test file must declare its tier tag; an untagged file compiles
        # in every run (leaking across tiers).
        test-tags = pkgs.runCommand "verseal-test-tags" { } ''
          untagged=$(grep -rL --include='*_test.go' -E '^//go:build (unit|integration|e2e)' ${goSrc} || true)
          if [ -n "$untagged" ]; then
            echo "test files missing a //go:build unit|integration|e2e tag:" >&2
            echo "$untagged" >&2
            exit 1
          fi
          touch $out
        '';
      };

      # Dev shortcuts (`nix run`) against the local working tree. CI-identical
      # hermetic runs = `nix flake check`. `test` = unit + integration (the
      # coverage tiers); e2e (subprocess) skips race.
      apps = {
        test = testApp "test" "unit,integration" true;
        "test:unit" = testApp "test-unit" "unit" true;
        "test:integration" = testApp "test-integration" "integration" true;
        "test:e2e" = testApp "test-e2e" "e2e" false;
        lint = devApp "lint" [
          go
          golangci-lint
        ] lintCmd;
      };
    };
}
