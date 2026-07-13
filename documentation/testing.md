# Testing Strategy

How we write tests in verseal. The live exemplars are
[`internal/version/version_test.go`](../internal/version/version_test.go) and
[`main_test.go`](../main_test.go); this document is the reasoning behind them.

## Framework

We use Go's standard `testing` package with [testify](https://github.com/stretchr/testify)
for assertions. This is the **xUnit** family (Kent Beck's SUnit to JUnit to the
rest): a test runner, suites, cases, and assertions. It is the same architecture
`jest`/`vitest` use, so the vocabularies map directly:

| Concept        | verseal (Go + testify)      | jest / vitest        |
| -------------- | --------------------------- | -------------------- |
| Suite / group  | `Test_...` func, `t.Run`    | `describe`           |
| Case           | `t.Run("name", ...)`        | `it` / `test`        |
| Assertion      | `assert.*` / `require.*`    | `expect`             |
| Setup/teardown | (avoided, see Hermeticity)  | `beforeEach`         |

The body of every test follows **Arrange, Act, Assert** (AAA). AAA is the same
thing BDD calls Given, When, Then.

## Structure

**One suite per unit under test.** The suite function is the `describe` block;
its `t.Run` subtests are the cases.

Name suites `Test_<unit|integration|e2e>_<Subject>`, for example
`Test_unit_ApplyBump`. The `_` after `Test` is valid Go. The middle segment
classifies the test (see Unit, integration, e2e); the last names the subject:
the function under test for unit/integration, or the flow/command for e2e
(`Test_e2e_ReleaseFlow`).

`t.Run` is `describe` and **nests to any depth**, so group related cases when it
helps:

```go
func Test_unit_ParseCommit(t *testing.T) {
    t.Run("conventional", func(t *testing.T) {
        // cases ...
    })
    t.Run("breaking change footer", func(t *testing.T) {
        // cases ...
    })
}
```

This runs as `Test_unit_ParseCommit/conventional/...` and filters with
`-run Test_unit_ParseCommit/conventional`.

## Table-driven cases

Each suite is a table of cases. The slice is `tests`, the loop element is `test`:

```go
tests := []struct {
    name     string
    input    string
    bump     Bump
    expected string
}{
    {"patch increments the patch", "1.2.3", Patch, "1.2.4"},
    // ...
}
for _, test := range tests {
    t.Run(test.name, func(t *testing.T) {
        // Arrange
        base := mustVersion(t, test.input)

        // Act
        result := ApplyBump(base, test.bump)

        // Assert
        assert.Equal(t, test.expected, result.String())
    })
}
```

- Label the phases with `// Arrange`, `// Act`, `// Assert`. Omit a phase that has
  nothing to do (a pure function whose inputs come straight from the table has
  only Act and Assert).
- The comparison triad is `input` produces `result`, checked against `expected`.
- One behavior per suite. Split combined tests (`Max` and `String` are
  `Test_unit_Max` and `Test_unit_String`).

## Assertions: `require` vs `assert`

Choose by role, not by habit.

- **`require.*`** stops the test on failure (`t.FailNow`). Use it for guards and
  preconditions, where continuing would panic or be meaningless. Example:
  `require.NoError(t, err)` before using the returned value.
- **`assert.*`** records the failure and continues (`t.Fail`). Use it for the
  Assert phase's behavioral checks, so all failures in a case report at once.

Do not blanket-`require` the assertions.

## Naming

Two rules, held together:

- **No abbreviations.** `bump`, not `b`; `mustVersion`, not `mustV`.
- **No overnaming.** Use the shortest full word that is unambiguous in its
  context. In a test the loop element is `test`, not `scenario` or `testCase`.

The comparison variables are `result` (the Act output) and `expected` (the table
field). These deviate from Go's idiomatic `got`/`want`; we prefer the clearer
words.

## Hermeticity

**Every test builds its own world.** No lifecycle hooks (`SetupTest` and the
like) and no shared fixture state by default. A test that fails should be
readable and reproducible on its own, without tracing setup that ran elsewhere.

Shared setup and common data are an **optimization**, added only when duplication
or setup cost demands it, never upfront. For the same reason we do **not** use
testify's `suite` package yet: its value is lifecycle hooks and shared struct
state, exactly what we are declining. When a real integration test needs
expensive shared setup (a temporary git repository, a database), prefer explicit
constructor helpers plus `t.Cleanup` over hooks, and reach for `suite` only if
those clearly win.

## Unit, integration, e2e

The middle segment is the test pyramid, and all three levels use the same
framework, structure, and conventions above (testify, `t.Run`, AAA, naming,
hermeticity). They differ only in scope and in what the AAA phases do.

- **unit** (`Test_unit_*`): pure and fast, no I/O. The bulk of the suite.
- **integration** (`Test_integration_*`): exercises one real boundary
  (filesystem, git, network) directly against the package API.
- **e2e** (`Test_e2e_*`): drives the built `verseal` binary as a subprocess
  against a real world, asserting on stdout, stderr, and exit code. Arrange
  builds the binary and sets up a temporary environment (for example a git repo);
  Act runs the command; Assert checks the observable output. This is the only
  level that tests the program as a user invokes it.

Hermeticity holds at every level: an e2e test builds its own temp world, no
shared hooks. e2e simply has a heavier Arrange, which is legitimate real setup,
not a shared fixture.

## Build tags and gating

**Every test file carries exactly one tier tag** as its first line:

```go
//go:build unit

package version
```

This is deliberate. A file with no build tag compiles in *every* run, so an
untagged test would leak across tiers (a `-tags e2e` run would also drag in every
untagged unit file). Tagging all files makes each run select its tier cleanly. A
`test-tags` flake check enforces that no `*_test.go` is left untagged.

Because everything is tagged, a bare `go test ./...` with no tags compiles
nothing. Every tier is a Nix target instead:

| Target | Tags | Notes |
| --- | --- | --- |
| `nix run .#test` | `unit,integration` | the default run, and the coverage source |
| `nix run .#test:unit` | `unit` | fast inner loop |
| `nix run .#test:integration` | `integration` | real boundaries |
| `nix run .#test:e2e` | `e2e` | drives the built binary |

The hermetic checks mirror this: `checks.test` gates unit+integration (and emits
the coverage profile), `checks."test:e2e"` gates e2e.

**Coverage spans unit and integration.** A single `go test -tags unit,integration`
run compiles both tiers (a file whose tag is in the set is included), so the one
profile covers both with no profile-merging. **e2e is not in this number**: an
e2e test's `-coverprofile` measures the test harness, not the subprocess binary.
Real e2e coverage needs the binary-coverage path (`go build -cover` + `GOCOVERDIR`
+ `go tool covdata`), folded in later, not merged into this profile.

The dev shell sets `GOFLAGS=-tags=unit`, so in `nix develop` a plain `go test`
and gopls both default to the unit tier; an explicit `-tags integration` on the
command line overrides it. `.golangci.yml` sets `run.build-tags: [unit,
integration, e2e]` so the linter still sees tagged test files.

> Nix note: `nix flake check` only sees git-tracked files. New files (including
> `go.sum` and any new `_test.go`) must be `git add`ed or the sandbox will not
> see them, silently testing less than you think.
