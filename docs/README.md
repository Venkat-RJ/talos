# Talos documentation

Start here if you are new to the project. The onboarding guides assume you can
program in some language (Python, JavaScript, Rust, anything) but have never
used Lean, written WebAssembly by hand, or touched a proof assistant.

## New to Talos? Read in this order

| Step | Guide | What you get |
|------|-------|--------------|
| 1 | [Concepts](onboarding/01-concepts.md) | The mental model: what Wasm is, what Lean is, and why "the interpreter is the spec" matters. Ends with a Python/JavaScript-to-Lean phrasebook and a glossary. |
| 2 | [Getting started](onboarding/02-getting-started.md) | Install the toolchain, run a Wasm program, then write and check your first proof. About an hour, most of it waiting for the first build. |
| 3 | [Reading a proof](onboarding/03-reading-a-proof.md) | A line-by-line walk through three real examples: a straight-line function, a trap, and a loop. |
| 4 | [Your first contribution](onboarding/04-first-contribution.md) | What newcomers can usefully work on, the fork-to-merge workflow, the house rules, and what CI checks. |
| 5 | [Repository map](onboarding/05-repo-map.md) | Reference: every directory, the key definitions and where they live, the `just` recipes, and the runner CLI. |

If you only have ten minutes, read the first two sections of
[Concepts](onboarding/01-concepts.md) and then run the
[Getting started](onboarding/02-getting-started.md) quick start.

## Other documents

- [`std_guide.md`](std_guide.md): adding one Rust standard-library function to
  CodeLib and reusing it from another crate. The `just verifier-*` workflow it
  describes is current. Its Lean snippets use the retained big-step `wp` API;
  present-day CodeLib proofs are written against the small-step machine (see
  `codelib/CodeLib/RustStd/U64/AbsDiff.lean` for the current style).
- [`../verifier/README.md`](../verifier/README.md): the Rust to Wasm to Lean
  pipeline tool.
- [`../verifier/SPECIFICATIONS.md`](../verifier/SPECIFICATIONS.md): how to phrase
  a public specification for a Rust export.
- [`../differential/README.md`](../differential/README.md): differential testing
  of the runner against V8.
- [`../IirisMigration.md`](../IirisMigration.md): the small-step and iris-lean
  migration plan and its status.
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md): the contribution guidelines.
- [`../AGENTS.md`](../AGENTS.md) and [`../CLAUDE.md`](../CLAUDE.md): guidance
  for AI coding agents. Useful to humans too, since they state the load-bearing
  rules (kernel-checked proofs, fuel-free specs, keep the interpreter simple).
