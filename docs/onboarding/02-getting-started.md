# Getting started: run a Wasm program, then prove one

You will install the Lean toolchain, build the Talos interpreter, run a
WebAssembly program from the command line, write a program of your own, and
finish by writing a Lean proof that your program is correct for every input.
By the end you will have seen the full loop that every contribution to Talos
goes through: write, build, check.

Every command and every code snippet in this guide was run against the
repository at the time of writing. If something here does not work, that is a
bug in the guide; please open an issue or a pull request.

## What you'll need

- macOS or Linux. Windows works through WSL.
- `git`.
- About 10 GB of free disk. The shared Lean dependency cache (`.lake/packages`,
  mostly Mathlib) is roughly 7 GB, and the interpreter's own build output is
  under 1 GB.
- Roughly an hour, most of it waiting for the first build.

You do **not** need Rust, `wasm-tools`, or `just` for this guide. They matter
later, for the Rust-to-Wasm pipeline and the spec testsuite; the
[first contribution](04-first-contribution.md) guide says when to install them.

## Step 1: Install elan

`elan` manages Lean versions the way `nvm` or `pyenv` manage Node and Python.
It reads the `lean-toolchain` file in each package and fetches the pinned
version on first use.

```bash
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh
```

Restart your shell (or `source ~/.profile`) and check:

```bash
elan --version
```

You should see a version number. The exact Lean version is installed later,
automatically, the first time you run `lake` inside the repository.

## Step 2: Clone the repository

The spec testsuite is a git submodule, so clone with submodules. If you plan to
contribute, fork on GitHub first and clone your fork instead.

```bash
git clone --recurse-submodules https://github.com/cajal-technologies/talos.git
cd talos
```

If you already cloned without submodules, run
`git submodule update --init` inside the repo.

## Step 3: Build the interpreter

Build the `interpreter/` package first. It is the foundation the other packages
depend on, and it is enough for everything in this guide.

```bash
cd interpreter
lake exe cache get
lake build
```

What happens:

- `lake exe cache get` downloads prebuilt Mathlib files. Without this step Lake
  would compile Mathlib from source, which takes hours. The first run also
  fetches the pinned Lean version through `elan`.
- `lake build` compiles the interpreter and checks every proof in it, including
  all the worked examples under `Interpreter/Wasm/Examples/`.

Budget 20 to 60 minutes for the first build depending on your machine and
network. Later builds only recompile what changed. Warnings about `sorry` or
unused variables would be real problems, but a clean checkout should finish
with no output other than progress lines.

`just build` at the repo root builds all three packages; skip that for now.

## Step 4: Run a Wasm program

Still in `interpreter/`:

```bash
lake exe runner samples/factorial.wat fact 5
```

Output:

```
120
```

You just ran WebAssembly through an interpreter whose every instruction is a
Lean definition with theorems attached. Try a few more:

```bash
lake exe runner samples/factorial.wat fact 13
```

```
1932053504
```

That is not 13! (6227020800). Wasm `i32` arithmetic wraps modulo 2^32, and
the interpreter faithfully reproduces that. Keep this in mind for the proof
later.

```bash
lake exe runner samples/trap.wat div_by_zero
```

```
trap: integer divide by zero
```

The exit code is 1. A trap is Wasm's runtime abort, and it is specified
behaviour, not an interpreter failure.

```bash
lake exe runner --fuel 5 samples/factorial.wat fact 5
```

```
out of fuel
```

Exit code 2. `--fuel` caps the number of machine steps. Five is not enough for
factorial of 5. Fuel exists because Lean functions must terminate; it is a
proof device and never part of a specification.

Run `lake exe runner --help` for the full CLI. Exit codes: 0 success, 1 trap,
2 out of fuel, 3 any other error (bad arguments, unknown export, decode
failure).

## Step 5: Write your own Wasm program

Create a file `double.wat` anywhere (this example uses `/tmp`):

```wat
(module
  (func $double (export "double") (param i32) (result i32)
    local.get 0
    local.get 0
    i32.add))
```

Line by line: `local.get 0` pushes the first parameter onto the operand stack.
The second `local.get 0` pushes it again. `i32.add` pops both and pushes their
sum. The function returns whatever is on top when its body ends.

```bash
lake exe runner /tmp/double.wat double 21
```

```
42
```

## Step 6: Write your first proof

Now the part that makes Talos different. You will state, in Lean, that
`double` returns `x + x` for every 32-bit input, and have the compiler check
it.

Create `interpreter/Interpreter/Wasm/Examples/Double.lean` with this content:

```lean
import Interpreter.Wasm.SmallStep

/-! Tutorial example: `double(x) = x + x`. -/

namespace Wasm
open SmallStep

/-- The body of the function: push local 0 twice, then add. -/
def Double : Program := [.localGet 0, .localGet 0, .add]

def doubleModule : Module :=
  { funcs := [{ params := [.i32], results := [.i32], body := Double }] }

/-- The machine state at the moment the function starts running on input `x`. -/
def doubleConfig (x : UInt32) : Config Unit :=
  { expr := .running
      { locals := { params := [.i32 x] }
        code := Double
        resultArity := 1
        callerRemainder := [] }
    store :=
      { runtime := { instances := #[{ module := doubleModule, host := {} }], entry := ⟨0⟩ }
        wasm := doubleModule.initialStore } }

/-- Concrete check: double(21) = 42. -/
theorem double_21 :
    (runSteps 4 (doubleConfig 21)).result.values? = some [.i32 42] := by
  decide +kernel

/-- Symbolic proof: for every x, the function returns `x + x`. -/
theorem double_steps (x : UInt32) :
    Steps (doubleConfig x)
      [.instruction (.localGet 0), .instruction (.localGet 0),
       .instruction .add, .administrative .finish]
      ⟨.done [.i32 (x + x)], (doubleConfig x).store⟩ := by
  wasm_steps [(.localGet rfl), (.localGet rfl), .add]
  exact Steps.single .finish

theorem double_terminates (x : UInt32) :
    TerminatesWith (doubleConfig x) (fun values _ => values = [.i32 (x + x)]) :=
  TerminatesWith.of_steps (double_steps x) rfl

theorem double_partial (x : UInt32) :
    PartiallyMeets (doubleConfig x) (fun values _ => values = [.i32 (x + x)]) :=
  (double_terminates x).toPartiallyMeets

end Wasm
```

Check the file on its own, without rebuilding the package:

```bash
lake env lean Interpreter/Wasm/Examples/Double.lean
```

No output means every theorem in the file was accepted. It takes a few seconds.

What each block does:

- **`Double`** is the program as Lean data. Compare it with the WAT: same three
  instructions, written as constructors of the `Instruction` type. `Program` is
  just `List Instruction`.
- **`doubleModule`** wraps the body in a function with one `i32` parameter and
  one `i32` result. Fields you leave out take their defaults.
- **`doubleConfig x`** is the starting snapshot of the machine: expression
  `running` with parameter 0 set to `x`, the code to execute, one expected
  result, and a store holding this one module. Every example in the repository
  builds a config this way.
- **`double_21`** is the concrete check. `runSteps 4` executes at most four
  steps (three instructions plus the administrative `finish` step that turns a
  finished body into a `done` result). `decide +kernel` has Lean's kernel
  evaluate the run and confirm the answer.
- **`double_steps`** is the real theorem. It says: starting from `doubleConfig
  x`, the machine takes exactly these four steps and ends in `done [x + x]`
  with the store unchanged. `wasm_steps` applies one `Step` constructor per
  instruction. `.localGet rfl` needs a proof that local 0 really holds the value
  it pushes; `rfl` supplies it because both sides compute to the same thing.
  `.add` needs no side condition. The last step, `.finish`, is administrative:
  it packages the operand stack into the result.
- **`double_terminates`** lifts the trace to the public, fuel-free statement:
  there is a terminating run whose result is `[x + x]`.
- **`double_partial`** is the weaker partial-correctness form, derived in one
  line from the total form.

## Step 7: Break it, to see what a failing proof looks like

Change `42` to `43` in `double_21` and re-run `lake env lean`:

```
Double.lean:28:2: error: Tactic `decide` proved that the proposition
  (runSteps 4 (doubleConfig 21)).result.values? = some [Value.i32 43]
is false
```

Lean did not just fail to prove the claim; it evaluated the program and proved
the claim false. Put `42` back.

Now change both occurrences of `x + x` to `x * 2` and run again. This time the
error is a type mismatch at `Steps.single .finish`: the `finish` step produces
`done [x + x]` (because that is what the `add` instruction left on the stack),
but the theorem statement asked for `done [x * 2]`. The two are equal for every
`UInt32`, but Lean will not take your word for it; you would need a rewriting
step to bridge them. This is the everyday experience of proof writing: the
checker is exact, and the gap between "obviously equal" and "syntactically
equal" is where the work is.

Put `x + x` back and confirm the file checks cleanly again.

## Step 8: Set up your editor

Everything above works from the terminal, but proofs are written
interactively. Install the **Lean 4** extension in VS Code (the extension id is
`leanprover.lean4`). Open the `talos` folder. Then open your `Double.lean`.

Click anywhere inside a `by` block. The **Lean Infoview** panel shows the
current goal at that point: the hypotheses above the line, the statement still
to prove below it. Move the cursor line by line through `double_steps` and
watch the goal shrink as each step is applied. This panel is how you will
understand every proof you read and write from here on.

If the extension reports that it cannot find imports, make sure the package
has been built (Step 3) and that the file lives under a package directory
with a `lakefile.toml` (here, `interpreter/`).

## What you built

You have a working Talos checkout, you ran WebAssembly through the verified
interpreter, and you proved a theorem about a program of your own that holds
for all 4,294,967,296 possible inputs. The file you wrote follows the exact
pattern every example in `Interpreter/Wasm/Examples/` uses:

1. program as data;
2. module and starting `Config`;
3. a concrete check with `decide +kernel`;
4. a symbolic `Steps` trace built with `wasm_steps`;
5. lifting to `TerminatesWith` and `PartiallyMeets`.

`Double.lean` is a learning file, not a contribution: the repository already
has examples covering `add`. Delete it, or keep it out of your commits.

Next: [Reading a proof](03-reading-a-proof.md) walks through three real
examples, including a trap and a loop with an invariant. When you are ready to
change something, [Your first contribution](04-first-contribution.md) has the
workflow and the house rules.

## Troubleshooting

**`lake exe cache get` fails or says the package is missing.** Run
`lake update` in `interpreter/`, then retry. The `just lake-shared` recipe does
exactly this pair.

**The build is compiling Mathlib files (paths under `.lake/packages/mathlib`)
and has been running for a very long time.** The cache step was skipped or
failed. Stop the build, run `lake exe cache get` again, then `lake build`.

**`just: command not found`.** `just` is a command runner used by the repo's
convenience recipes. Install it with `brew install just` (macOS) or your
package manager, or run the underlying `lake` commands directly; every recipe
in the `justfile` is one or two lines.

**`wasm-tools not found on PATH`.** You passed a `.wasm` file. The runner reads
`.wat` directly and only needs `wasm-tools` to decode binaries. Either convert
the file yourself or install `wasm-tools` (`brew install wasm-tools` or
`cargo install wasm-tools`).

**`error: module declares imports (N), runner has no host environment`.** The
module imports host functions (for example stdio). The CLI runner has no host;
modules with imports are exercised from Lean, see
`Interpreter/Wasm/Examples/UniversalHost.lean`.

**Everything rebuilds after switching branches.** Expected. Lake rebuilds
anything whose dependencies changed, and `SmallStep.lean` is upstream of almost
everything.

**The machine runs out of memory during `lake build`.** `SmallStep.lean` is
large and elaborates with a high heartbeat limit. Close other heavy
applications and run `lake build` again; it resumes from the last module that
finished.

**A proof that used to work now fails after pulling.** Someone changed the
semantics or renamed a lemma. Read the error, then look at the corresponding
example under `Examples/` for the current idiom.
