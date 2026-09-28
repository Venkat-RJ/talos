# Repository map

A reference to what lives where. Skim once, then come back when you need to
find something. Paths are relative to the repository root. Line numbers are
deliberately omitted because they rot; search for the identifier instead.

## Top level

| Path | What it is | Read it when |
|------|------------|--------------|
| `README.md` | Project overview and quick start. | First. |
| `CONTRIBUTING.md` | Contribution guidelines, good starting points, code of conduct. | Before your first PR. |
| `AGENTS.md`, `CLAUDE.md` | Rules for AI coding agents. Also the most compact statement of the house rules for humans. `AGENTS.md` is the more current of the two. | When unsure whether something is allowed. |
| `IirisMigration.md` | Plan and status of the small-step and iris-lean migration. | To understand why both a big-step `run` and a small-step `Step` exist. |
| `docs/` | This documentation. | |
| `justfile` | Command recipes. `just` with no arguments lists them. | Whenever you want to build, test, or run something. |
| `lean-toolchain` | Pinned Lean version. Each package has an identical copy. | When `elan` misbehaves. |
| `testsuite_report.txt` | Committed snapshot of every spec-test outcome. CI regenerates and diffs it. | When your change might affect spec coverage. |
| `scripts/` | Shell and Python helpers used by `just` and CI. | When a recipe does something surprising. |
| `vendor/testsuite/` | The official WebAssembly spec testsuite (git submodule). | When a testsuite run fails. |
| `.lake/packages/` | Shared third-party dependencies (Mathlib, iris-lean, ...). About 7 GB. Not committed. | Never edit; delete to force a re-fetch. |
| `.github/workflows/` | CI definitions. | Before opening a PR. |
| `.claude/`, `.codex/`, `.agents/` | Editor and AI-agent configuration, including a worktree bootstrap hook. | Only if you use those tools. |

## The Lean packages

### `interpreter/` (Lake package `Interpreter`)

The Wasm formalisation. Everything else depends on it.

| Path | Contents |
|------|----------|
| `Interpreter.lean` | Umbrella import: the public surface plus the bundled examples. |
| `Interpreter/Wasm.lean` | Umbrella for the core API, with a docstring listing every module. |
| `Interpreter/Wasm/Syntax.lean` | The AST: `ValueType`, `Value`, `Instruction`, `Program` (alias for `List Instruction`), `Function`, `Module`, imports, exports, GC types. Read before assuming what is supported. |
| `Interpreter/Wasm/SmallStep.lean` | The authoritative semantics. `Config`, `Expr`, `ThreadState`, `ControlFrame`, `CallFrame`, `TrapReason`, `StepKind`, the `Step` relation, `stepChecked?` and its soundness and completeness proofs, `Steps`, `wasm_steps`, `runSteps`, `RunnerResult`, `TerminatesWith`, `PartiallyMeets`, `TrapsWith`, and the lifting lemmas. Around 7,600 lines. |
| `Interpreter/Wasm/Semantics.lean`, `Semantics/Lemmas.lean` | The retained big-step interpreter (`execOne`, `exec`, `run`) and its lemmas. A regression oracle; not what the runner executes. |
| `Interpreter/Wasm/Locals.lean` | `Locals` (params, locals, operand stack) and helpers. |
| `Interpreter/Wasm/Mem.lean`, `Float.lean`, `IEEE754.lean`, `Simd.lean` | Linear memory, float operations over bit patterns, IEEE-754 details, the `v128` type. |
| `Interpreter/Wasm/Validate.lean` | Module validation (static type checking). |
| `Interpreter/Wasm/Decoder/Wat.lean` | The WAT text-format parser. `Decoder/ProofEval.lean` supports decoding inside proofs. |
| `Interpreter/Wasm/Host.lean`, `Host/*.lean` | Host functions a module can import: `StdIO`, `Random`, `OOM`; `Registry` resolves imports by name; `Universal` bundles every host and is the default for specifications. |
| `Interpreter/Wasm/Spec/Defs.lean`, `Spec/Termination.lean` | Fuel-free predicates for the big-step API and the `FuncSpec` bridge. |
| `Interpreter/Wasm/Wp/*.lean` | The weakest-precondition calculus over the big-step semantics: definitions, atomic rules, `block`/`loop`/`call` rules, and the `wp_run` tactic. |
| `Interpreter/Wasm/MeasureTermination.lean` | Helpers for termination arguments by a decreasing measure. |
| `Interpreter/Wasm/LeanSyntax.lean` | Compact elaborators for generated modules, such as `hexBytes%`, which expands a hex string to a `List UInt8` literal. |
| `Interpreter/Wasm/Examples/` | Worked examples, one file each, all imported from `Examples/Basic.lean`. `Harness.lean` holds shared projections (`runValues`, `runTrapMsg`, `decodeOrDefault`). Start with `IsEven.lean`, `TrapDivZero.lean`, `SimpleLoop.lean`, `Factorial.lean`, `Gcd.lean`. |
| `Interpreter/Runner.lean` | The `runner` CLI executable. |
| `Interpreter/Testsuite.lean`, `Testsuite/Exec.lean` | The `testsuite` executable that drives `.wast` files. |
| `samples/` | Three tiny `.wat` files for the runner: `factorial.wat`, `sum_to.wat`, `trap.wat`. |
| `lakefile.toml` | Declares the `Interpreter` library and the `runner` and `testsuite` executables; requires Mathlib. |

### `codelib/` (Lake package `CodeLib`)

Reusable reasoning infrastructure for compiled Rust. Downstream code imports
`CodeLib`, never the interpreter directly.

| Path | Contents |
|------|----------|
| `CodeLib.lean` | Umbrella import. Every module intended for downstream use is listed here. |
| `CodeLib/Attrs.lean` | The `@[spec_of ...]` and `@[proves ...]` attributes. |
| `CodeLib/Entry.lean`, `Basic.lean`, `Equivalence.lean`, `List.lean`, `UInt32.lean`, `UInt64.lean`, `WordCodec.lean`, `ByteReassembly.lean` | General lemmas: entry-point bridging, program equivalence, integer and byte-level facts. |
| `CodeLib/RustStd/` | Proved contracts for Rust standard-library functions as compiled to Wasm: `U64/` (one file per operator), `Array/`, `MemArray`, `MemFillLoop`, `MemCopyLoop`, `Frame`, `Region`. |
| `CodeLib/SepLogic/` | Separation-logic layer over the small-step machine via iris-lean: `WasmHeap`, `WasmRules`, the `SmallStep*` language, state, lifting, and adequacy modules, plus several worked examples. |
| `CodeLib/Host/StdIO.lean` | Host-side reasoning for stdio. |
| `CodeLib/Examples/` | Larger case studies: `MergeSort`, `Quicksort`, `SelectionSort`, `Gcd`, `UInt32Array`. |
| `CodeLib/Near/` | State, environment, and proofs for the NEAR contract host model. |
| `CodeLib/Generated.lean` | What generated `Program.lean` files import. Defines `watFunctionBody%`, which embeds one function body from a `.wat` file at compile time. |
| `lakefile.toml` | Requires the interpreter (by path) and `iris-lean` (pinned git revision). |

### `programs/` (Lake package `Project` in `programs/lean/`)

Concrete Rust crates and proofs about their compiled Wasm.

| Path | Contents |
|------|----------|
| `rust/Cargo.toml` | Cargo workspace listing every crate and per-crate optimisation levels. |
| `rust/<crate>/src/lib.rs`, `src/exports.rs` | The Rust source. `exports.rs` holds the `#[unsafe(no_mangle)] pub extern "C"` wrappers that define what the verifier sees. |
| `rust/build/<crate>/program.wasm`, `program.wat` | Build outputs, produced by `just verifier-build`. The `.wat` is committed because `Program.lean` embeds it. |
| `rust/talos_stdio/` | The shared Rust support crate giving programs `read` and `write` over the stdio host. |
| `lean/Project.lean` | Imports every crate's `Spec` and proof modules. |
| `lean/Project/<Crate>/Program.lean` | Generated by `verifier emit`. Do not edit. |
| `lean/Project/<Crate>/Spec.lean` and siblings | Hand-written specification and proofs. Small crates have one file; `Mergesort/` and `GcdStdio/` split proofs across several. |
| `lean/HexEncodeStdio/`, `lean/HexDecodeStdio/` | Two additional Lake libraries with the hex codec proofs. |
| `lean/lakefile.toml` | Requires `CodeLib` by path. |

### `verifier/` (Lake package `Verifier`)

The CLI that drives Rust to Wasm to Lean. See `verifier/README.md`.

| Path | Contents |
|------|----------|
| `Verifier/Main.lean` | Subcommands: `init`, `add`, `del`, `build`, `emit`, `lift`, `prove`, `check`, `extract`, `report`. |
| `Verifier/Emit.lean`, `EmitFidelity.lean`, `EmitRoundTrip.lean` | Generating `Program.lean` from `.wat` and checking it round-trips. |
| `Verifier/Extract*.lean`, `RustExtract.lean` | Reading `@[spec_of]`/`@[proves]` tags and Rust exports into JSON. `EXTRACT.md` documents the format. |
| `SPECIFICATIONS.md` | How to phrase a public spec (`Input`, `Output`, `args`, `result`, `Runs`). |
| `template/` | Project, crate, and module templates copied by `init`/`add`/`emit`. |
| `report/` | Astro site that renders extracted coverage. |

### `differential/`

Differential testing of the runner against V8 through the external `miscast`
tool. `differential/README.md` explains modes and seeds.

## Key definitions and where they live

| Name | File | One line |
|------|------|----------|
| `Instruction`, `Program`, `Function`, `Module`, `Value`, `ValueType` | `interpreter/Interpreter/Wasm/Syntax.lean` | The AST. |
| `Locals` | `interpreter/Interpreter/Wasm/Locals.lean` | params, locals, operand stack. |
| `Config`, `Expr`, `ThreadState`, `MachineStore`, `ControlFrame`, `CallFrame` | `interpreter/Interpreter/Wasm/SmallStep.lean` | Machine state. |
| `TrapReason`, `InternalError`, `StepKind`, `AdministrativeStep` | same | Outcomes and step labels. |
| `Step`, `Steps`, `wasm_steps` | same | The relational semantics and the tactic that walks it. |
| `stepChecked?`, `stepChecked?_sound`, `stepChecked?_complete` | same | The executable step and its correspondence proofs. |
| `runSteps`, `RunnerResult`, `TraceResult`, `initConfig` | same | Fuel-bounded execution and how a run starts. |
| `TerminatesWith`, `PartiallyMeets`, `TrapsWith`, `TerminatesWithOutcome` | same | Fuel-free specification predicates. |
| `runSteps_eq_success_of_steps`, `runSteps_values_terminates`, `runSteps_trapped_trapsWith` | same | Lifting lemmas. |
| `Module.initialStore` | `interpreter/Interpreter/Wasm/Syntax.lean` | The store a module starts with. |
| `Wasm.Universal.State`, `Universal.envFor`, `Universal.RunsExport`, `Universal.PartiallyRunsExport` | `interpreter/Interpreter/Wasm/Host/Universal.lean` | The default host for specifications and its run predicates. |
| `ExportCall`, `ExportReturn` | `interpreter/Interpreter/Wasm/Host/Run.lean` | Semantic call and return records used by public specs (see `verifier/SPECIFICATIONS.md`). |
| `Decoder.Wat.decode` | `interpreter/Interpreter/Wasm/Decoder/Wat.lean` | WAT text to `Module`. |
| `watFunctionBody%` | `codelib/CodeLib/Generated.lean` | Embed a `.wat` function body at compile time. |
| `spec_of`, `proves` | `codelib/CodeLib/Attrs.lean` | Spec and proof attributes. |

## `just` recipes

Run `just` with no arguments at the repo root to list them. Grouped:

| Recipe | Does |
|--------|------|
| `just build` | `lake update` and `lake exe cache get` in `interpreter/`, then `lake build` in `programs/lean` (which builds codelib and interpreter first). |
| `just build-interpreter`, `build-codelib`, `build-programs`, `build-verifier` | Build one package. |
| `just runner-build` | Build the runner executable. |
| `just runner-run <args>` | `lake exe runner <args>` from `interpreter/`. |
| `just runner-smoke` | Smoke-test the runner against `samples/`. |
| `just testsuite [pattern]` | Run the spec testsuite, optionally filtered by filename substring. Needs `wasm-tools`. |
| `just testsuite-report` | Regenerate `testsuite_report.txt`. Refuses to run unless `wasm-tools` matches the pinned version in the `justfile`. |
| `just differential [args]` | Differential test against V8 via miscast. Needs `wasm-tools`, `python3`, `git`, `node` 22+. |
| `just rust-build`, `rust-test`, `rust-lint` | Cargo build, test, and clippy across `programs/rust`. Needs Rust. |
| `just verifier-init <path>` | Scaffold a new verification project. |
| `just verifier-add <crate>`, `verifier-del <crate>` | Add or remove a crate in `programs/`. |
| `just verifier-build [crates]` | Compile Rust to wasm and wat. |
| `just verifier-emit [--force-emit] [crates]` | Generate `Program.lean` and scaffold `Spec.lean`. |
| `just verifier-lift <crate> <funcidx> <Type> <name>` | Scaffold a reusable CodeLib theorem for one function. |
| `just verifier-prove [crates]` | `lake build` the selected Lean modules. |
| `just verifier-check [--force-emit] [--no-prove] [crates]` | build, emit, prove in one go. |
| `just verifier-extract [crates]`, `verifier-report [crate]` | Extract JSON metadata; build the HTML report. |
| `just clean` | Remove build artefacts from all packages. |

## The `runner` CLI

```
lake exe runner [--fuel N] [-h|--help] <file> <method> [args...]
```

Run from `interpreter/`.

| Argument | Meaning |
|----------|---------|
| `<file>` | `.wat` is read directly. `.wasm` is decoded via `wasm-tools print`, which must be on `PATH`. |
| `<method>` | An export name, or a non-negative integer taken as a function index. The integer rule wins. |
| `[args...]` | One literal per declared parameter. Integers: decimal or `0x` hex. Floats: WAT literal grammar (`1.5`, `-0x1.8p+2`, `inf`, `nan`). Reference-typed params accept only `null`. |
| `--fuel N` | Step cap. Default 1,000,000. |

| Exit code | Meaning | stderr |
|-----------|---------|--------|
| 0 | Success. Results printed to stdout, one per line. | |
| 1 | Trap. | `trap: <reason>` |
| 2 | Out of fuel. | `out of fuel` |
| 3 | Any other error: bad arguments, unknown export, decode failure, module with imports (the CLI has no host environment). | `error: <message>` |

## Scripts

| Script | Used by | Does |
|--------|---------|------|
| `scripts/testsuite.sh` | `just testsuite` | Runs the `testsuite` executable, optionally filtered. |
| `scripts/testsuite-report.sh` | `just testsuite-report`, CI | Regenerates the report with the pinned `wasm-tools`. |
| `scripts/differential.sh` | `just differential` | Drives miscast against the runner. |
| `scripts/runner-smoke.sh` | `just runner-smoke` | Runs the runner over `samples/`. |
| `scripts/axiom-audit.py` | CI | Lists axioms every declaration depends on and flags disallowed ones. |
| `scripts/clean.sh` | `just clean` | Deletes build artefacts. |
| `scripts/codex-worktree-setup.sh`, `.claude/worktree-init.sh` | AI-agent tooling | Seed a git worktree's `.lake` from the main checkout so builds start warm. |

## Continuous integration

| Workflow | Trigger | Summary |
|----------|---------|---------|
| `.github/workflows/lean_action_ci.yml` | push to `main`, every PR | Four jobs. **Build CodeLib proofs**: `codelib` with `--wfail` plus the axiom audit over interpreter, codelib, and verifier. **Build program wasm**: compiles the Rust crates on Linux. **Build program proofs**: `programs/lean` with `--wfail` against those wasm bytes, plus its axiom audit. **Smoke test**: builds the `Interpreter` library and the runner (this is the only job that compiles `Examples/`) and runs `just runner-smoke`. |
| `.github/workflows/testsuite-report.yml` | PRs to `main` | Regenerates `testsuite_report.txt` and fails if it differs from the committed file. |
| `.github/workflows/verifier-freshness.yml` | push to `main`, every PR | Re-runs `verifier emit` and fails if any committed `Program.lean` is stale. |

## External tools and versions

| Tool | Version | Needed for |
|------|---------|------------|
| Lean | pinned in `lean-toolchain` (installed by `elan`) | Everything. |
| `just` | any recent | Convenience recipes. Optional; every recipe is a short `lake` or script call. |
| `wasm-tools` | pinned as `WASM_TOOLS_VERSION` in the `justfile` | Decoding `.wasm`, the spec testsuite, `testsuite_report.txt`, the verifier pipeline. |
| Rust toolchain | pinned in `programs/rust/rust-toolchain.toml` | Building `programs/rust` crates. |
| Node.js | 22 or newer | Differential testing (V8 oracle) and the verifier report site. |
| Python 3 | any recent | Differential testing and the axiom audit. |
