# verseal

**Sealed versioning** -> *verseal* = **ver**sion + **seal**.

**Deterministic version computation, bound to a signed integrity ledger.**

verseal computes a project's next [semantic version](https://semver.org) as a
pure, replayable function of its git history. Same history, same version, on any
machine. It records each release in a signed, append-only ledger that
binds `version → revision`, verifiable offline without trusting a forge or CI.

## Goals

- **Deterministic versioning** - the next version is a pure function of
  `(history, classifier, policy)`, so it can be re-derived and audited. Semver is
  the target because a version is a compatibility contract, the Liskov
  Substitution Principle across time.
- **Integrity ledger** - a signed, tamper-evident, repo-local record binding each
  release tag to its source revision. The version-label → revision mapping is
  otherwise a mutable pointer nothing guards.
- **Driven, not root** - works standalone, but designed to be dispatched by a
  build system that owns the project graph.

## Development

Everything runs through Nix; `nix flake show` lists every target. Start with
the [development guide](./documentation/development.md), then
[build-system.md](./documentation/build-system.md) and
[testing.md](./documentation/testing.md) for the reasoning.

## AI usage

We understand the benefits of AI and do not block their use with this project. However, we will close submissions that have not been reviewed by contributors or are blatantly ai-only.

verseal is developed collaboratively with AI, not delegated to it. Design,
research, documentation, and code is done under human direction and review. 

Disclosed in the spirit of the project: trust should be explicit, including trust in how
the software itself was built.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
