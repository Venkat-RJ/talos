# Talos concepts for people who have never used Lean or Wasm

This guide gives you the mental model behind Talos. It assumes you can program
in Python, JavaScript, or something similar, and nothing else. By the end you
will know what WebAssembly and Lean each are, why Talos combines them, and what
the words in the code mean. Nothing here requires installing anything; the
hands-on part is in [Getting started](02-getting-started.md).

## Talos in one paragraph

Talos is a WebAssembly (Wasm) interpreter written in Lean 4. Lean is both a
programming language and a proof checker. That combination lets one set of
definitions do two jobs: *run* a Wasm program on concrete inputs, and *prove*
theorems about what the program does on all inputs. There is no separate
"specification" document to keep in sync with the code. The interpreter is the
specification.

## If you come from Python or JavaScript

Three shifts in thinking cover most of the surprise.

**Tests check some inputs. Proofs check all of them.** In pytest or Jest you
write `assert f(2) == 3`, maybe a property-based test that samples a thousand
random inputs. In Lean you can still do the concrete check, but you can also
state `theorem f_correct (x : UInt32) : f x = x + 1` and the compiler will not
accept the file until the claim is proven for every one of the 2^32 possible
inputs. A passing build means every theorem in the codebase holds.

**The compiler is the test runner.** There is no `pytest` or `npm test` in
Talos. `lake build` (Lake is Lean's build tool, like npm or cargo) compiles the
code and checks every proof. If a proof is wrong, the build fails with an error
pointing at the exact line. Red build means a false claim or an incomplete
proof.

**Speed is deliberately not the goal.** The interpreter is written to be easy
to reason about, not fast. A Python or Node developer would reach for a clever
data structure; here the simple linked list wins because it is easier to unfold
inside a proof. Performance work is welcome, but only as a separate
implementation that is proven equivalent to the simple one.

## WebAssembly in ten minutes

WebAssembly is a low-level instruction format. Compilers for Rust, C, C++, Go,
and others can target it. Browsers run it, and so do standalone runtimes.

**It is a stack machine.** Instructions push values onto an operand stack and
pop them off. If you have ever looked at Python bytecode with the `dis` module
(`LOAD_FAST`, `BINARY_ADD`) or at JVM bytecode, this is the same idea. Here is
the sample `interpreter/samples/factorial.wat`, with the stack shown after
each instruction:

```wat
(module
  (func $fact (export "fact") (param i32) (result i32) (local i32)
    ;; param 0 is n; local 1 is the accumulator, acc
    i32.const 1        ;; stack: [1]
    local.set 1        ;; acc = 1              stack: []
    loop
      local.get 0      ;; stack: [n]
      i32.eqz          ;; stack: [n == 0 ? 1 : 0]
      if               ;; pops the flag. nonzero: run the (empty) then-branch
      else             ;; zero: run this branch
        local.get 1    ;; stack: [acc]
        local.get 0    ;; stack: [acc, n]
        i32.mul        ;; stack: [acc * n]
        local.set 1    ;; acc = acc * n        stack: []
        local.get 0
        i32.const 1
        i32.sub        ;; stack: [n - 1]
        local.set 0    ;; n = n - 1            stack: []
        br 1           ;; jump back to the start of the loop
      end
    end
    local.get 1))      ;; stack: [acc]  the function returns the top value
```

**Two formats, same program.** The text above is WAT (WebAssembly Text), a
Lisp-like syntax with parentheses. The binary form is `.wasm`. Talos reads WAT
directly and uses the external `wasm-tools` program to turn `.wasm` into WAT.

**Four numeric types.** `i32` and `i64` are 32- and 64-bit integers; `f32` and
`f64` are floats. Integers have no separate signed and unsigned type. Instead
each *instruction* says how to interpret the bits: `i32.div_u` is unsigned
division, `i32.div_s` is signed. Talos also models the reference types (function
references, externref, exception references, GC references) and the 128-bit
SIMD vector type.

**Arithmetic wraps.** `i32.add` computes modulo 2^32. Running `fact 13` through
the sample gives 1932053504, not 6227020800, because 13! does not fit in 32
bits. This is why the factorial theorem in Talos states its result as
`UInt32.ofNat n.toNat.factorial`: the true factorial, then wrapped.

**Errors are traps.** Dividing by zero, reading memory out of bounds, or hitting
the `unreachable` instruction aborts execution with a *trap*. A trap is not a
bug in the interpreter; it is the specified behaviour, and Talos proves theorems
about when a program traps.

**Control flow is structured.** There is no `goto`. `block`, `loop`, and `if`
open labelled regions; `br n` breaks out to the `n`-th enclosing label (or, for
a `loop`, jumps back to its start). `br_if n` does the same conditionally.

**Functions, locals, and modules.** A function has parameters, extra local
variables, and a body. Parameters are locals too: `local.get 0` reads the first
parameter. Functions live in a *module*, which can also declare a linear
memory (a big byte array), globals, tables, and *imports*: functions the host
environment provides, such as reading stdin.

## Lean in ten minutes

Lean 4 is a functional programming language whose type system is strong enough
to state and check mathematical theorems.

**Definitions look like functions in any language.**

```lean
def double (x : Nat) : Nat := x + x
```

`Nat` is the type of natural numbers (unbounded, like Python `int` when it is
non-negative). `UInt32` is the 32-bit wraparound type Wasm `i32` values live in.

**A theorem is a definition whose type is a statement.**

```lean
-- One input, checked by evaluation.
theorem double_21 : double 21 = 42 := by decide

-- Every input, checked by proof.
theorem double_eq (x : Nat) : double x = 2 * x := by
  unfold double
  omega
```

Read `theorem name (args) : statement := proof`. The part after the colon is
the claim; the part after `:=` is the evidence. `by` switches into *tactic
mode*, where you give the proof as a sequence of commands: `decide` evaluates a
decidable claim; `unfold` replaces `double x` by its definition; `omega` closes
goals about linear integer arithmetic. There are dozens of tactics; the
[Reading a proof](03-reading-a-proof.md) guide covers the handful Talos uses
most.

**The kernel checks everything.** Tactics are convenience: they produce a proof
term, and a small trusted core (the kernel) checks that term. Talos requires
that every proof be kernel-checked. In particular, new code must not use
`native_decide`, which trusts the compiler instead of the kernel. Use
`decide +kernel` for concrete evaluation; it makes the kernel do the computing.

**`sorry` is a placeholder, not a proof.** Writing `sorry` closes any goal with
a warning. Talos builds with warnings treated as errors in CI, so a `sorry`
anywhere fails the build.

**Mathlib is the standard library of mathematics.** Talos depends on it for
facts about numbers, lists, and factorials. It is large (several gigabytes
compiled), which is why the first build downloads a prebuilt cache.

## The core idea: the interpreter is the spec

Most verified-software projects have a specification (a document, or a
mathematical model) and an implementation, plus a proof that the two agree.
Keeping three artefacts in sync is the hard part.

Talos collapses this. The Lean function that executes a Wasm instruction is
also the mathematical object you prove things about. When you prove
`factorial_terminates`, you are proving a fact about the very code that the
command-line runner executes. If the interpreter has a bug, the proof either
fails or proves something false-looking, and either way you have found the bug.

## The small-step machine

The heart of the interpreter is in `interpreter/Interpreter/Wasm/SmallStep.lean`.
Four types describe a running program.

```
Config ───┬── expr : Expr ──┬── running (thread : ThreadState)   still executing
          │                 ├── done    (values : List Value)     finished normally
          │                 └── trapped (reason : TrapReason)     aborted with a trap
          └── store : MachineStore                                memory, globals, tables,
                                                                  loaded module instances

ThreadState ──┬── locals : Locals        params, locals, and the operand stack
              ├── code   : Program       the instructions still to run (a List Instruction)
              ├── control : List ControlFrame   open block/loop/if labels
              └── calls   : List CallFrame      suspended callers
```

A `Config` is a snapshot of the whole machine. `Expr` tells you whether it is
still running, finished with a list of result values, or trapped. The
`ThreadState` inside `running` holds what a debugger would show you: the
variables, the remaining instructions, and the stack of open control regions.

Execution is described two ways, and Talos proves they agree:

- **`Step config kind config'`** is a *relation*: a mathematical statement that
  the machine can move from `config` to `config'` in one step of kind `kind`
  (usually "execute this one instruction"). It is an inductive type with one
  constructor per instruction. This is the semantics you prove things about.
- **`stepChecked? config`** is a *function* that computes the next
  configuration. The theorems `stepChecked?_sound` and `stepChecked?_complete`
  prove it returns exactly what `Step` allows. This is the semantics you run.

`Steps config trace config'` chains many steps into a trace. `runSteps fuel
config` iterates `stepChecked?` at most `fuel` times and returns a
`RunnerResult`: `success`, `trapped`, `outOfFuel`, or `internalError`.

A proof about a program typically exhibits a `Steps` trace, then uses a lemma
such as `runSteps_eq_success_of_steps` to conclude what `runSteps` computes.

## Fuel, and why specs never mention it

Lean functions must terminate, and a Wasm program might loop forever. The
standard trick is *fuel*: `runSteps` takes a number and gives up with
`outOfFuel` when it hits zero. Fuel is a proof device, not part of what a
program "does", so public specifications never mention it. Instead they use
three fuel-free predicates from `SmallStep.lean`:

| Predicate | Meaning | Name for it |
|-----------|---------|-------------|
| `TerminatesWith config post` | There is a finite trace from `config` to a `done` state, and `post` holds of the result. | total correctness |
| `PartiallyMeets config post` | Every finite trace from `config` to a `done` state satisfies `post`. Says nothing if the program loops forever or traps. | partial correctness |
| `TrapsWith config reason post` | There is a finite trace from `config` to `trapped reason`, and `post` holds of the final store. | trap specification |

`TerminatesWith` implies `PartiallyMeets` (the theorem is called
`toPartiallyMeets`). Most examples prove the strong form and derive the weak
one.

## Traps versus internal errors

Two different things can stop a run early, and the distinction matters when you
read results.

- A **trap** (`TrapReason`) is Wasm-level behaviour: divide by zero, out of
  bounds memory access, `unreachable`. It is part of the semantics, and
  programs are proven to trap in specific situations.
- An **internal error** (`InternalError`) means the machine reached a state that
  module validation should have ruled out: a malformed operand stack, an index
  out of range, an unresolved import. It signals a bug or an invalid module,
  never normal Wasm behaviour.

## From Rust source to a theorem

The `programs/` package proves things about real compiled code. The pipeline:

```
programs/rust/<crate>/src/lib.rs          hand-written Rust
        │  cargo build --target wasm32-unknown-unknown
        ▼
programs/rust/build/<crate>/program.wasm  binary
        │  wasm-tools print
        ▼
programs/rust/build/<crate>/program.wat   text
        │  verifier emit
        ▼
programs/lean/Project/<Crate>/Program.lean   generated; embeds each function
        │                                     body via the watFunctionBody% macro
        │  you write this part
        ▼
programs/lean/Project/<Crate>/Spec.lean      hand-written specification + proof
        │  lake build
        ▼
        proof checked by the Lean kernel
```

Two attributes tie it together. `@[spec_of "rust-exported" "crate::fn"]` marks
a Lean proposition as the specification of a Rust function.
`@[proves SpecName]` marks a theorem as its proof. The `verifier extract`
command reads those tags to report coverage.

The `verifier/` tool drives this pipeline and is invoked through `just
verifier-*` recipes. You need the Rust toolchain and `wasm-tools` to run it;
you do not need either to build the Lean proofs, because the `.wat` files are
committed.

## The packages and how they depend

```
interpreter/     Lake package "Interpreter"
   │             Wasm AST, small-step machine, decoder, runner, examples
   ▼
codelib/         Lake package "CodeLib"
   │             reusable lemmas about Rust std functions, memory regions,
   │             separation-logic rules (via iris-lean)
   ▼
programs/lean/   Lake package "Project"
                 one directory per Rust crate: Program.lean + Spec.lean

verifier/        Lake package "Verifier"   the CLI tool (depends on interpreter only)
```

Downstream code imports `CodeLib`, never the interpreter directly. All four
packages share one dependency tree at the repo root, `.lake/packages`, so
Mathlib is downloaded once.

Two advanced layers exist that you do not need on day one. The **WP calculus**
(`interpreter/Interpreter/Wasm/Wp/`) is a "weakest precondition" framework: a
way to compute, from a desired postcondition, what must be true before a block
runs. **Iris** (via the `iris-lean` dependency in CodeLib) is a separation
logic used to reason about memory ownership when proving Rust programs that
allocate. Both are for proofs about compiled Rust; the hand-built examples in
`interpreter/` use neither.

## Phrasebook: Python and JavaScript to Lean

| You know | In Lean | Notes |
|----------|---------|-------|
| `def f(x): return x + 1` | `def f (x : Nat) : Nat := x + 1` | Return type after the colon. No `return` keyword; the body is an expression. |
| `x: int` / `x: number` | `(x : Nat)`, `(x : UInt32)` | `Nat` is unbounded. `UInt32` and `UInt64` wrap like Wasm `i32` and `i64`. |
| `assert f(2) == 3` in a test | `theorem t : f 2 = 3 := by decide` | Checked at build time, for that one input. |
| property-based test over random `x` | `theorem t (x : Nat) : ... := by ...` | Covers every `x`, not a sample. |
| `None` / `null`, `Optional[T]` | `Option T` with values `none` and `some v` | |
| `[1, 2, 3]`, list | `[1, 2, 3] : List Nat` | A linked list. `x :: xs` prepends. `Array T` is the contiguous kind. |
| `Enum`, tagged union, TS discriminated union | `inductive Color where \| red \| green` | Constructors. `.red` is shorthand when the type is known. |
| `@dataclass`, object literal, TS interface | `structure Point where x : Nat; y : Nat` | Build with `{ x := 1, y := 2 }`. Update with `{ p with x := 5 }` (like spread). |
| `match` / `switch` | `match c with \| .red => ... \| .green => ...` | Must cover every case. |
| `import a.b.c` | `import Interpreter.Wasm.SmallStep` | Module name is the file path with dots. |
| module namespace, `import * as` | `namespace Wasm ... end Wasm`, `open SmallStep` | `open` lets you write `Config` instead of `SmallStep.Config`. |
| `x if c else y` | `if c then x else y` | |
| `lambda x: x + 1`, `x => x + 1` | `fun x => x + 1` | |
| `# comment` | `-- comment` | `/-- doc -/` before a definition is its docstring; `/-! ... -/` is a section comment. |
| `print(...)` debugging, REPL | `#eval expr`, `#check expr`, `#print name` | Shown in the editor's infoview, not at runtime. |
| `package.json`, `pyproject.toml` | `lakefile.toml` | |
| `npm`, `pip`, `cargo` | `lake` | `lake build`, `lake exe runner ...`, `lake env lean file.lean`. |
| `nvm`, `pyenv`, `rustup` | `elan` | Reads `lean-toolchain` and installs the pinned Lean version. |
| `package-lock.json` | `lake-manifest.json` | |
| `node_modules/` | `.lake/packages/` | Shared at the repo root. Build output is in each package's `.lake/build/`. |
| `Makefile`, npm scripts | `justfile` | `just build`, `just testsuite`. |
| function that may fail, returns `null` | name ends in `?`, returns `Option` | `values?`, `stepChecked?`. |
| function that throws on bad input | name ends in `!` | `funcs[0]!` panics if empty. |
| generic `<T>`, `TypeVar` | `(α : Type)` or implicit `{α}` | `Config α` is generic over the host state type; examples use `Config Unit`. |
| `Result<T, E>`, try/except | `Except ε α` with `.ok v` / `.error e` | |
| type annotation you trust the compiler to infer | `_` | Lean fills in what it can work out. |

## Glossary

- **AST.** Abstract syntax tree. The Lean data types (`Instruction`, `Function`,
  `Module`) that represent a Wasm program after decoding.
- **Axiom.** A statement accepted without proof. Lean has a few built in
  (propositional extensionality, choice, quotients). CI runs an audit that
  lists which axioms each declaration depends on; `native_decide` adds one
  Talos does not allow in new code.
- **Big-step.** The older interpreter style in `Semantics.lean`: one recursive
  function `run` that evaluates a whole function call. Retained for regression
  comparison; not what the runner executes.
- **Config.** A snapshot of the small-step machine: an `Expr` plus a
  `MachineStore`.
- **decide +kernel.** A tactic that proves a decidable proposition by having the
  kernel evaluate it. The kernel-checked replacement for `native_decide`.
- **Differential testing.** Running the same Wasm module in Talos and in a
  trusted engine (V8) and flagging any difference. See `differential/`.
- **elan.** The Lean toolchain manager. Installs the version named in
  `lean-toolchain`.
- **Export.** A function a module makes callable by name from outside.
- **Fuel.** A step budget passed to `runSteps` so the function is guaranteed to
  terminate. Never appears in a public specification.
- **Host function / import.** A function the module expects the environment to
  supply, such as `stdio.read`. `Wasm.Universal` is a host that provides every
  import Talos knows about, resolved by name.
- **Infoview.** The panel in the Lean editor extension that shows the current
  proof goal at the cursor. The main way to understand and write proofs.
- **Invariant.** A property that holds at the top of every loop iteration. Loop
  proofs state it at an explicit `Config` and prove each iteration preserves it.
- **Iris / separation logic.** A logic for reasoning about ownership of memory.
  CodeLib uses the `iris-lean` library for proofs about Rust programs that
  touch linear memory.
- **Kernel.** Lean's small trusted proof checker. "Kernel-checked" means the
  kernel verified the proof term, with no compiled code trusted.
- **Lake.** Lean's build system and package manager.
- **Lifting lemma.** A theorem that converts a fact about one layer into a fact
  about another. `runSteps_eq_success_of_steps` lifts a `Steps` trace to a
  `runSteps` result; `runSteps_values_terminates` lifts that to
  `TerminatesWith`.
- **Locals.** A function's parameters, extra local variables, and operand stack,
  bundled in one structure.
- **Mathlib.** The community mathematics library for Lean. A dependency.
- **Module instance.** A loaded module plus its resolved imports. The
  `MachineStore` holds an array of them.
- **olean.** A compiled Lean file, kept in `.lake/build/`. Importing a module
  loads its olean instead of re-elaborating the source.
- **Operand stack.** The value stack Wasm instructions push to and pop from.
  Stored in `Locals.values`.
- **Partial correctness.** "If it finishes, the answer is right." Does not rule
  out looping forever. `PartiallyMeets`.
- **Program.** In Talos, `Program` is an alias for `List Instruction`.
- **Small-step.** Executing one instruction at a time and describing each
  transition. The authoritative semantics in Talos.
- **sorry.** A placeholder that closes any proof goal with a warning. Fails CI.
- **spec_of / proves.** Attributes linking a Lean proposition to a Rust function
  and a theorem to that proposition. Read by `verifier extract`.
- **Store.** The shared mutable state of a Wasm instance: memory, globals,
  tables. `MachineStore` adds the loaded module instances.
- **Tactic.** A command in a `by` block that transforms the current goal.
  `simp`, `omega`, `decide`, `exact`, `apply`, `rfl`.
- **Testsuite / wast.** The official WebAssembly specification tests, in
  `vendor/testsuite/`, written in `.wast` (WAT plus assertions). Run with
  `just testsuite`.
- **Total correctness.** "It finishes, and the answer is right."
  `TerminatesWith`.
- **Trace.** A list of `StepKind`s recording which steps a run took.
- **Trap.** Wasm's runtime abort. A `TrapReason` names the cause.
- **Validation.** Static checks a module must pass before it runs (types line
  up, indices in range). `Validate.lean`.
- **Verifier.** The CLI in `verifier/` that turns Rust crates into Lean
  `Program.lean` files and checks the proofs.
- **WAT.** WebAssembly Text format.
- **WP.** Weakest precondition. A predicate transformer: given what you want
  true afterwards, compute what must be true before. `Wp/` directory.

## Where to go next

[Getting started](02-getting-started.md) installs the toolchain and has you run
and prove a program in about an hour. If you would rather read code first,
[Reading a proof](03-reading-a-proof.md) walks through three real examples.
