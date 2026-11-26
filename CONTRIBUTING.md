# Contributing to HALean

Thanks for your interest in contributing. HALean is a function-by-function
translation of Home Assistant's core into Lean 4 — an automation engine, templates,
scripts, helpers and the state/event/service core — so it can be formally verified and
still track upstream. This guide covers how to build it, the standards we hold code to,
and how to send a change. It follows the shared contribution standard used across the
[Beneficial AI Foundation](https://github.com/Beneficial-AI-Foundation) Lean projects.

## Prerequisites

Install [`elan`](https://github.com/leanprover/elan), the Lean toolchain manager.
It reads `lean-toolchain` and fetches the exact Lean/Lake version this project uses,
so you don't install Lean by hand:

```sh
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh
```

Running the test suites additionally needs [`uv`](https://github.com/astral-sh/uv)
(it installs the pinned Python and dependencies for the scenario, differential and
sun comparisons). The Docker demo needs only Docker.

## Building

The executables are **not** default targets: every `lean_exe` root declares a
top-level `main`, so they are built by name (`lakefile.toml`).

```sh
lake build                       # the HALean library: the engine and all proofs
lake build halean-automation halean-script halean-template halean-sun-grid \
  halean-core halean-core-states halean-core-services halean-core-events \
  halean-helpers                 # the service executables
```

HALean builds on Linux, macOS and Windows; released engine binaries are published for
all three, plus a multi-arch Docker image (see the `Release` and `Binaries` workflows
and the project's GitHub Releases).

## Testing

```sh
uv run tests/run_scenarios.py          # behaviour scenarios (engine only)
uv run tests/run_script_scenarios.py   # script scenarios
uv run tests/differential/run.py       # scenarios + templates vs a real Home Assistant
uv run --with astral==2.2 tests/sun/compare.py   # sunrise/sunset vs astral
lake env lean tools/Axioms.lean        # axiom audit of every HALean theorem
```

The differential and live tests drive a pinned Home Assistant release and can be
network- and CPU-heavy; continuous integration (`.github/workflows/lean_action_ci.yml`)
runs the build, the axiom audit and the scenario and differential suites on every push
and pull request. Please make sure the build and the suites relevant to your change pass
locally before opening a PR.

## Proof discipline

Correctness here comes from machine-checked proofs, so the sources must stay free of
proof escape hatches:

- **No `sorry`, `admit` or `native_decide`.** The axiom audit (`tools/Axioms.lean`,
  run in CI) pins every theorem to `propext`, `Classical.choice` and `Quot.sound`;
  `sorry` introduces `sorryAx` and `native_decide` introduces `Lean.ofReduceBool`,
  neither of which is allowed, so either one reachable from a theorem fails the audit.
- Decide concrete goals with `decide` / `rfl`, not `native_decide`.

## Submitting a change

1. **Branch** off `master` (or fork the repository).
2. Keep each pull request focused, and add or update a spec/test for behaviour you
   change — tests are theorems here. When you change a translated service, keep
   `manifest.yaml` and the drift check (`tools/drift.py`) in sync.
3. Make sure `lake build`, the executables you touched, the axiom audit and the
   relevant test suites pass, and that CI is green.
4. Write a clear PR description: what changed, why, and how you verified it.
5. By contributing, you agree your contribution is licensed under this repository's
   license (Apache 2.0, see `LICENSE`), and you certify the
   [Developer Certificate of Origin](https://developercertificate.org/) — add a
   `Signed-off-by: Your Name <you@example.com>` line to your commits (`git commit -s`).

## Reporting issues

Open a GitHub issue with a clear title, what you expected, what happened, and the
smallest scenario or configuration that reproduces it. Security-sensitive reports can
be sent privately to **support@beneficialaifoundation.org** instead of a public issue.

## Code of conduct

Be respectful and constructive. Harassment or abuse is not tolerated. Maintainers may
remove comments, commits or contributions that don't meet this standard.
