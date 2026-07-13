# Build System

Nix is the build system. GitHub Actions only dispatches `nix` commands; nothing
builds outside a derivation.

## The mental model: derivations are the task graph

Nix has no task-runner feature because it does not need one. A derivation is a
task node: its inputs are the store paths it references, its command is the
builder, its output is cached by input hash. **An edge exists exactly where one
node splices another node's output (`${...}`)**. There is no `dependsOn` to
declare and none to drift: if a task does not reference an output, it does not
depend on it, and Nix will happily build them in parallel.

Where an Nx-style system gives you named targets, declared inputs, and a cached
graph, the Nix equivalents are:

| Nx concept | Nix equivalent here |
| --- | --- |
| target (`build`, `test`, `lint`) | derivation under `packages.*` / `checks.*` |
| `dependsOn` | a `${...}` reference to the other node's output |
| `inputs` (file globs for cache key) | `lib.fileset` filtered sources |
| task runner (`nx run`) | `nix build .#x`, `nix flake check`, `nix run .#x` |
| task list | `nix flake show` (apps display their exact command) |
| remote cache | the Nix store + Cachix |

To inspect the graph: `nix derivation show -r .#checks.<system>.test` prints a
node and its closure; `nix-tree` browses it interactively.

## The graph

One `buildGoModule` node (`base`) owns all builder mechanics: the module
proxy, source setup, and go invocation. Every task is a declarative variant of
it (`overrideAttrs`). The Rust ecosystem converged on the same shape (naersk
introduced the shared deps-only artifact; crane refined it into a
function-per-task API):

```
go.mod + go.sum ──> deps proxy (refetches only when deps change)
                        │
Go files (goSrc) ──> base ─┬─> packages.default              native, unit tests certify it (doCheck)
                           ├─> packages.verseal-<os>-<arch>  cross variants (GOOS/GOARCH, doCheck off)
                           ├─> checks.test                   coverage variant, unit+integration+race
                           ├─> checks."test:e2e"
                           └─> checks.lint                   (+ .golangci.yml via lintSrc)
Go files only ────────────────> checks.test-tags             tier-tag guard
packages.default ─────────────> checks.build
checks.test ──────────────────> packages.coverage            same node, second name
```

Filtered sources are the cache keys: a docs or workflow edit invalidates
nothing but the formatting check and the commit-stamped binary; a code edit
reruns tests and lint but never refetches dependencies; only a `go.mod`/`go.sum`
change rebuilds the dependency proxy. Check variants clear the version stamp so
the commit hash does not invalidate them.

## Layout

The flake is an index over one-concern modules (flake-parts `imports`):

- `flake.nix` inputs, systems, and the module list. Nothing else.
- `nix/toolchain.nix` the environment: Go pin, filtered sources, shared
  command strings. Exported to the other modules as the `toolkit` module
  argument.
- `nix/tasks.nix` the task graph: `base` plus every package, check, and app.
- `nix/dev.nix` developer experience: treefmt, pre-commit hook, dev shell.

A task is a set of attributes on `base` (`checkFlags`, `env.GOOS`, a
`checkPhase`), not a hand-rolled script: the builder mechanics live in
nixpkgs' `buildGoModule`, which maintains them across Go releases. Two
deliberate deviations from its defaults: `checkPhase` is replaced wholesale in
test variants (the default loops `go test` per package dir, which would
overwrite a single coverage profile), and the deps node is pinned to
`go.mod`/`go.sum` with a static name via `overrideModAttrs` (otherwise it would
embed the commit and refetch every commit).

## Tests: standalone nodes, not part of the package build

nixpkgs convention runs a package's tests inside its build (`doCheck`), which
certifies the stored artifact. The native package keeps that (unit tests run
inside `packages.default`). The richer gates are standalone `checks.*` nodes,
for two reasons of different weight:

- **Granular scheduling and attribution** (durable). Separate nodes run in
  parallel, fail attributably, and rebuild independently: changing lint config
  reruns only lint. This holds no matter where builds run; nixpkgs itself
  splits heavier tests out of packages for the same reason.
- **Cross-compiled artifacts cannot run their tests** (contingent on the
  single-runner constraint). A darwin binary built on a Linux runner has no
  host to execute on, so tests-in-package is impossible for most of today's
  package matrix.

The gate is `nix flake check`, which runs every check node. A package in the
store is not itself proof that tests passed; a green `nix flake check` on that
commit is.

## Cross-compilation: compiler-level, not derivation-level

Everything in this section is a bridge, forced by having one Linux runner
rather than a builder per architecture.

Idiomatic Nix cross is `pkgsCross.<target>` (a per-target stdenv). We instead
run Go's own cross-compiler (`GOOS`/`GOARCH`, CGO off) inside native
derivations. This is NON-STANDARD Nix and deliberate:

- Nix cross cannot practically produce darwin from Linux (the Apple SDK is not
  redistributable); Go can, because pure Go needs no target SDK.
- One runner and one toolchain closure build all four arches, with no
  per-target cache misses.

The tradeoff: cross-built artifacts are never executed by the build.

### What changes with native builders per arch

Once each architecture has a native builder (remote builders or per-arch CI
runners), the bridge dismantles:

- The `cross` variants, the `GOOS`/`GOARCH` overrides, and the
  `bin/<goos>_<goarch>` normalization disappear: every arch builds its own
  `packages.default`, natively.
- Every artifact becomes test-certified (`doCheck` runs everywhere), and each
  system's check nodes run natively (`nix flake check --all-systems` dispatched
  across builders).
- `dist` reshapes from "four cross variants" to "each system's native package,
  aggregated".

What stays regardless: standalone check nodes (the granularity argument), the
test-tier tags, the coverage node, the pinned deps proxy, filtered sources as
cache keys, and the module layout. Only the cross machinery is scaffolding.

## Commands

| Intent | Command |
| --- | --- |
| build for this machine | `nix build` |
| build one release artifact | `nix build .#verseal-<os>-<arch>` |
| build all release artifacts | `nix build .#dist` (one `result/` with `verseal-<os>-<arch>` binaries) |
| run all gates (CI) | `nix flake check` |
| coverage report | `nix build .#coverage` |
| dev loop tests | `nix run .#test` (also `.#test:unit`, `.#test:integration`, `.#test:e2e`) |
| focused test run | `nix run .#test:unit -- -run Test_unit_Max` (args pass through to `go test`) |
| lint | `nix run .#lint` |
| format | `nix fmt` |

Inside `nix develop` (or via direnv), the shell itself is the dev loop: bare
`go test ./...` runs the unit tier (`GOFLAGS=-tags=unit`), gopls sees tagged
test files, and `git commit` runs the staged treefmt + golangci-lint hook.

CI consumes the same graph, so steps after `nix flake check` are largely cache
hits: `checks.test` and `packages.coverage` are the same node, and
`checks.build` is `packages.default`. Only the cross artifacts add build work.

Caveat that costs hours: **the Nix sandbox sees only git-tracked files.** A new
untracked file is invisible to every hermetic task, which then passes on stale
input. `git add` new files before trusting `nix flake check`.
