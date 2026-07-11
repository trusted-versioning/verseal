# verseal

**Deterministic version computation, bound to a signed integrity ledger.**

verseal computes a project's next [semantic version](https://semver.org) as a
pure, replayable function of its git history — same history, same version, on any
machine. Later, it records each release in a signed, append-only ledger that
binds `version → revision`, verifiable offline without trusting a forge or CI.

## Goals

- **Deterministic versioning** — the next version is a pure function of
  `(history, classifier, policy)`, so it can be re-derived and audited. Semver is
  the target because a version is a compatibility contract — the Liskov
  Substitution Principle across time.
- **Integrity ledger** — a signed, tamper-evident, repo-local record binding each
  release tag to its source revision. The version-label → revision mapping is
  otherwise a mutable pointer nothing guards.
- **Driven, not root** — works standalone, but designed to be dispatched by a
  build system that owns the project graph.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
