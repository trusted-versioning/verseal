# Developer experience: formatting, the staged pre-commit hook, and the shell.
{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.git-hooks.flakeModule
  ];

  perSystem =
    {
      config,
      pkgs,
      toolkit,
      ...
    }:
    {
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
            package = toolkit.golangci-lint;
            # Same dir-loop the stock hook generates, plus CGO off: lint only
            # typechecks, and the hook must not require a C compiler (see
            # lintCmd in toolchain.nix).
            entry = pkgs.lib.getExe (
              pkgs.writeShellApplication {
                name = "precommit-golangci-lint";
                runtimeInputs = [ toolkit.golangci-lint ];
                text = ''
                  export CGO_ENABLED=0
                  mapfile -t dirs < <(printf '%s\n' "$@" | xargs -n1 dirname | sort -u)
                  for dir in "''${dirs[@]}"; do
                    golangci-lint run ./"$dir"
                  done
                '';
              }
            );
          };
        };
      };

      devShells.default = pkgs.mkShell {
        # Brings in the pre-commit CLI and hook tools (including golangci-lint),
        # and installs the git pre-commit hook on shell entry.
        inputsFrom = [ config.pre-commit.devShell ];

        packages = [
          toolkit.go
          pkgs.gopls
          pkgs.gotools
        ];

        # Nix owns the toolchain: never silently download a different Go
        GOTOOLCHAIN = "local";

        # Default dev + gopls to the unit tier so tagged test files are visible
        # and a bare `go test` runs units. Explicit `-tags integration|e2e`
        # overrides this (command-line flags win over GOFLAGS).
        GOFLAGS = "-tags=unit";
      };
    };
}
