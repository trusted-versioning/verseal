# Development Guide

Everything runs through Nix. There is nothing to install besides Nix itself
(and optionally direnv): no Go toolchain, no linters, no formatter versions to
match. If `nix flake check` is green locally, CI is green.

Companion docs: [build-system.md](./build-system.md) (how the task graph works
and why), [testing.md](./testing.md) (test conventions).

## Prerequisites

- Nix with flakes enabled (`experimental-features = nix-command flakes`)
- direnv (optional but recommended; the repo has an `.envrc`)

## First-time setup

```sh
git clone https://github.com/trusted-versioning/verseal && cd verseal
direnv allow        # or: nix develop
```

That drops you into the dev shell: pinned Go, gopls preconfigured for the
tagged test files, gotools, and the git pre-commit hook (treefmt +
golangci-lint on staged files) installed automatically.

## Discovering targets

```sh
nix flake show
```

That is the task list. Apps display the exact command they run. The three
invocation verbs, by what you are touching:

| Verb | Touches | Use for |
| --- | --- | --- |
| `nix run .#<app>` | your working tree | the dev loop |
| `nix flake check` | the git-tracked tree, hermetically | the gate CI runs |
| `nix build .#<package>` | the git-tracked tree, hermetically | artifacts |

## Day to day

Inside the dev shell the plain commands are already correct:

```sh
go test ./...                       # unit tier (GOFLAGS=-tags=unit is set)
go test -tags integration ./...    # explicit tier override
go build && ./verseal
```

Or from anywhere, without entering a shell:

```sh
nix run .#test                      # unit + integration, race on
nix run .#test:unit                 # fast inner loop
nix run .#test:unit -- -run Test_unit_Max    # args pass through to go test
nix run .#test:integration
nix run .#test:e2e
nix run .#lint
nix fmt
```

Before pushing:

```sh
git add <new files>                 # see gotcha below
nix flake check                     # exactly what CI runs
```

## Artifacts

```sh
nix build                           # native binary, test-certified: ./result/bin/verseal
nix build .#verseal-darwin-arm64    # one cross-compiled arch
nix build .#dist                    # all arches: result/verseal-<os>-<arch>
nix build .#coverage                # result/coverage.xml (unit + integration)
```

All four release arches build from any dev machine; darwin artifacts are
cross-compiled by the Go toolchain itself.

## Adding a dependency

`go.mod` is canonical; Nix consumes it through a pinned hash.

1. In the dev shell: `go get <module>` and use it, then `go mod tidy`.
2. In `nix/tasks.nix`, set `vendorHash = pkgs.lib.fakeHash;` on `base`.
3. `git add -u && nix build` and copy the `got: sha256-...` value from the
   mismatch error into `vendorHash`.
4. `nix flake check`.

The hash pins the full dependency set; it changes only when `go.mod`/`go.sum`
change. Never commit a `vendor/` directory.

## Where things live

| File | Owns |
| --- | --- |
| `flake.nix` | inputs, systems, module index. Nothing else. |
| `nix/toolchain.nix` | Go pin, filtered sources, shared command strings |
| `nix/tasks.nix` | the task graph: `base` + every package, check, and app |
| `nix/dev.nix` | treefmt, pre-commit hook, dev shell |
| `.golangci.yml` | lint rules (single source for CI, app, and hook) |

To add a task: a hermetic gate is a `base.overrideAttrs` variant (see the
`check` helper) added to `checks`; a dev shortcut is one `devApp`/`testApp`
line added to `apps`. Keep the command string in `nix/toolchain.nix` if both
need it, so they cannot drift.

## Upgrades

- **Go version**: bump `go = pkgs.go_1_XX` in `nix/toolchain.nix` and the
  `go` directive in `go.mod` together. `GOTOOLCHAIN=local` makes the Nix pin
  authoritative and fails loudly on drift.
- **nixpkgs and other inputs**: `nix flake update` (or
  `nix flake update <input>`), then `nix flake check`.

## Gotchas

- **The sandbox sees only git-tracked files.** An untracked file is invisible
  to every hermetic task: `nix flake check` can pass while testing less than
  you think, or fail claiming a file you can see does not exist. `git add`
  new files first. Dev apps (`nix run`) do not have this restriction; they use
  the working tree.
- **A bare `go test` outside the dev shell compiles nothing**: every test file
  carries a tier build tag and plain `go` does not know which tier you want.
  Use the apps, or work inside the shell where `GOFLAGS=-tags=unit` is set.
- **`vendorHash` mismatch after touching go.mod/go.sum**: expected; redo the
  fakeHash dance above.
- **x86_64-darwin**: not a dev platform (nixpkgs 26.11 dropped it); the
  `verseal-darwin-amd64` artifact still builds everywhere via cross-compile.
