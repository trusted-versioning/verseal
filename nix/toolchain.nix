# The build environment every task shares: the Go pin, filtered sources, and
# the command vocabulary. Exposed to the other modules as the `toolkit` module
# argument.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      go = pkgs.go_1_26;
      golangci-lint = pkgs.golangci-lint;

      # Build version = the commit, computed OUTSIDE the hermetic build and
      # injected as a stamp.
      version = inputs.self.shortRev or inputs.self.dirtyShortRev or "unknown";

      # Filtered sources: a task rebuilds only when files it actually consumes
      # change (docs or workflow edits invalidate nothing).
      modFiles = lib.fileset.unions [
        ../go.mod
        ../go.sum
      ];
      goFiles = lib.fileset.union modFiles (lib.fileset.fileFilter (file: file.hasExt "go") ../.);
      depsSrc = lib.fileset.toSource {
        root = ../.;
        fileset = modFiles;
      };
      goSrc = lib.fileset.toSource {
        root = ../.;
        fileset = goFiles;
      };
      lintSrc = lib.fileset.toSource {
        root = ../.;
        fileset = lib.fileset.union goFiles ../.golangci.yml;
      };

      # Tool commands, defined once so checks and apps can't drift. Every test
      # file carries a tier build tag (unit|integration|e2e), so a run selects
      # its tier explicitly; a bare `go test` would compile nothing.
      testCmd =
        tags: race:
        "go test -tags ${tags}${lib.optionalString race " -race"} -covermode=atomic -coverprofile=cover.out ./...";
      # CGO off: lint only typechecks; testify's transitive net import must not
      # require a C compiler (the lint app's PATH has none).
      lintCmd = "env CGO_ENABLED=0 golangci-lint run ./...";
    in
    {
      _module.args.toolkit = {
        inherit
          go
          golangci-lint
          version
          depsSrc
          goSrc
          lintSrc
          testCmd
          lintCmd
          ;
      };
    };
}
