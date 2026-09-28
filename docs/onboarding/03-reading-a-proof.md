# Reading a Talos proof

This guide walks through three real files from
`interpreter/Interpreter/Wasm/Examples/`, in increasing difficulty, and
explains every line. When you finish you will be able to open any example in
that directory and follow it, and you will know the small set of tactics and
lemmas that carry almost all of them.

Have the files open while you read. Better still, open them in VS Code with the
Lean extension and put your cursor inside each `by` block to watch the goal
change in the infoview.

## The shape every example shares

Every example has the same skeleton. Recognising it turns a wall of symbols
into five familiar moves.

```
1. Program as data          def Foo : Program := [...]
2. Module + starting Config def fooModule, def fooConfig (inputs) : Config Unit
3. A Steps trace            theorem foo_steps : Steps (fooConfig x) [trace] ⟨.done [...], store⟩
4. Lift to runSteps         theorem foo_runs  : (runSteps n (fooConfig x)).result = ...
5. Lift to fuel-free spec   theorem foo_terminates : TerminatesWith (fooConfig x) (fun values _ => ...)
                            theorem foo_partial    : PartiallyMeets ...  := (foo_terminates x).toPartiallyMeets
```

Not every file has all five (some skip step 4), and trap examples end in
`TrapsWith` instead. The theorem names follow this convention: `_steps` for the
trace, `_runs` for the `runSteps` fact, `_terminates`, `_partial`, and `_traps`
for the public statements.

## Example 1: a straight-line function (`IsEven.lean`)

The program tests whether a 32-bit value is even.

```lean
import Interpreter.Wasm.SmallStep

namespace Wasm
open SmallStep
```

`import` loads the small-step machine. `namespace Wasm` means every name
defined below is really `Wasm.something`. `open SmallStep` lets the file write
`Config` instead of `SmallStep.Config`.

```lean
def IsEven : Program := [.localGet 0, .const 1, .and, .eqz]
```

Push parameter 0, push 1, bitwise-and them (leaving `x & 1`, which is 1 for odd
and 0 for even), then `eqz` turns 0 into 1 and anything else into 0. Result: 1
if even, 0 if odd. The leading dot in `.localGet` is Lean's shorthand for
`Instruction.localGet`, allowed because the list's element type is known.

```lean
def isEvenModule : Module :=
  { funcs := [{ params := [.i32], body := IsEven, results := [.i32] }] }
```

A module with one function. `Module` and `Function` are structures with many
optional fields; you name only the ones you need.

```lean
def isEvenConfig (value : UInt32) : Config Unit :=
  { expr := .running
      { locals := { params := [.i32 value] }
        code := IsEven
        resultArity := 1
        callerRemainder := [] }
    store :=
      { runtime := { instances := #[{ module := isEvenModule, host := {} }], entry := ⟨0⟩ }
        wasm := isEvenModule.initialStore } }
```

The starting machine state for input `value`. `Config Unit` means "a config
whose host state type is `Unit`", i.e. no host state; modules that import stdio
would use a richer type. The `expr` is `running` with a `ThreadState`: the
parameter, the code, one expected result, nothing left over from a caller. The
`store` has a runtime with exactly one module instance and the module's initial
memory and globals. `⟨0⟩` is an anonymous-constructor: it builds a
`ModuleInstanceId` from the number 0.

```lean
def isEvenResult (value : UInt32) : UInt32 :=
  if (1 : UInt32) &&& value = 0 then 1 else 0
```

A plain Lean function stating what the answer *should* be. `&&&` is bitwise
and. Having a reference implementation like this in ordinary Lean makes the
theorem statement readable: "the Wasm program computes `isEvenResult`".

```lean
theorem isEven_runs (value : UInt32) :
    (runSteps 5 (isEvenConfig value)).result.values? =
      some [.i32 (isEvenResult value)] := by
```

The claim: running the machine for 5 steps from the start config gives a
successful result whose values are `[isEvenResult value]`. Five steps: four
instructions plus the administrative `finish`. The `?` in `values?` says it
returns an `Option`; it is `none` for traps or out-of-fuel.

```lean
  have hsteps : Steps (isEvenConfig value)
      [(.instruction (.localGet 0)), (.instruction (.const 1)),
       (.instruction .and), (.instruction .eqz), (.administrative .finish)]
      ⟨.done [.i32 (isEvenResult value)], (isEvenConfig value).store⟩ := by
```

`have name : statement := proof` proves an intermediate fact and names it.
This one is the `Steps` trace: from the start config, these five step kinds
lead to a `done` state with the expected value and an unchanged store.

```lean
    wasm_steps [(.localGet rfl), .const, .and, (.eqz rfl), .finish]
```

`wasm_steps` is a small macro defined in `SmallStep.lean`. Given a list of
`Step` constructors, it applies `Steps.cons` once per constructor, in order.
Each constructor is one rule of the semantics:

- `.localGet rfl`: the rule for `local.get`. It takes a proof that looking up
  the local yields the pushed value. `rfl` ("reflexivity") proves any equation
  whose two sides compute to the same thing.
- `.const`: no side condition.
- `.and`: no side condition.
- `.eqz rfl`: the rule takes a proof that the result equals
  `if value = 0 then 1 else 0`.
- `.finish`: the administrative step from an empty instruction list to `done`.

After these, the goal is whatever remains: here, that the machine's final
state matches the one the theorem named.

```lean
    by_cases h : value &&& (1 : UInt32) = 0 <;>
      simp [isEvenResult, h, UInt32.and_comm]
    all_goals exact Steps.refl _
```

The `eqz` rule computed `if (value &&& 1) = 0 then 1 else 0`, while the goal
mentions `isEvenResult value`, which is `if (1 &&& value) = 0 then ...`. Same
value, different spelling. `by_cases h : ...` splits into the two cases (the
and is zero, or it is not). `<;>` runs the next tactic on both resulting goals.
`simp [...]` rewrites using the definition of `isEvenResult`, the case
hypothesis `h`, and the commutativity of `&&&`. What is left is `Steps c [] c`,
closed by `Steps.refl`. `all_goals` applies it to every remaining goal.

```lean
  exact congrArg RunnerResult.values? (runSteps_eq_success_of_steps hsteps)
```

`runSteps_eq_success_of_steps` is a lifting lemma: from a `Steps` trace ending
in `done`, it concludes that `runSteps` with fuel equal to the trace length
returns `success` with those values. `congrArg f h` turns an equation `a = b`
into `f a = f b`; here it applies `values?` to both sides to match the theorem
statement exactly. `exact` says "this term is the whole proof".

```lean
theorem isEven_terminates (value : UInt32) :
    TerminatesWith (isEvenConfig value)
      (fun values _ => values = [.i32 (isEvenResult value)]) :=
  runSteps_values_terminates (isEven_runs value)
```

The public statement. `TerminatesWith config post` says some finite run ends in
`done` and `post` holds. The postcondition is a function of the result values
and the final store; `_` ignores the store. `runSteps_values_terminates` lifts
the `runSteps` fact. No `by` here: the proof is a single term, so `:=` is
enough.

```lean
theorem isEven_partial (value : UInt32) :
    PartiallyMeets (isEvenConfig value)
      (fun values _ => values = [.i32 (isEvenResult value)]) :=
  (isEven_terminates value).toPartiallyMeets

end Wasm
```

Partial correctness follows from total correctness in one step.

## Example 2: a trap (`TrapDivZero.lean`)

The program divides parameter 0 by parameter 1. It shows how one program gets
two specifications: one for the successful path and one for the trap.

```lean
def TrapDivZero : Program := [.localGet 0, .localGet 1, .divU]
```

```lean
theorem trapDivZero_steps_success (a b : UInt32) (hb : b ≠ 0) :
    Steps (trapDivZeroConfig a b)
      [(.instruction (.localGet 0)), (.instruction (.localGet 1)),
       (.instruction .divU), (.administrative .finish)]
      ⟨.done [.i32 (a / b)], (trapDivZeroConfig a b).store⟩ := by
  wasm_steps [(.localGet rfl), (.localGet rfl), (.divU hb)]
  exact Steps.cons .finish (Steps.refl _)
```

The theorem takes a hypothesis `hb : b ≠ 0`. The `divU` rule for the
non-trapping case requires exactly that proof, so `hb` is passed straight in.
`Steps.cons .finish (Steps.refl _)` is the long way of writing
`Steps.single .finish`: one more step, then stop.

```lean
theorem trapDivZero_steps_trap (a : UInt32) :
    Steps (trapDivZeroConfig a 0)
      [(.instruction (.localGet 0)), (.instruction (.localGet 1)),
       (.instruction .divU)]
      ⟨.trapped .integerDivideByZero, (trapDivZeroConfig a 0).store⟩ := by
  wasm_steps [(.localGet rfl), (.localGet rfl)]
  exact Steps.cons .divUZero (Steps.refl _)
```

Same program, divisor fixed at 0. The trace is one step shorter (no `finish`;
a trap is terminal) and ends in `trapped .integerDivideByZero`. The rule is
`.divUZero`, a separate constructor with no side condition because the divisor
is literally zero in the state.

```lean
theorem trapDivZero_runs_trap (a : UInt32) :
    (runSteps 3 (trapDivZeroConfig a 0)).result =
      .trapped .integerDivideByZero (trapDivZeroConfig a 0).store :=
  runSteps_finalConfig_of_steps (trapDivZero_steps_trap a)

theorem trapDivZero_traps (a : UInt32) :
    TrapsWith (trapDivZeroConfig a 0) .integerDivideByZero
      (fun store => store = (trapDivZeroConfig a 0).store) :=
  runSteps_trapped_trapsWith_store (trapDivZero_runs_trap a)
```

The lifting pattern again, with the trap-flavoured lemmas.
`TrapsWith config reason post` is the public statement: a finite run traps
with `reason`, and `post` holds of the final store.

## Example 3: a loop (`Factorial.lean`)

Loops are where proofs get real. The program is the factorial from
[Getting started](02-getting-started.md), built with `loop`, an inner `block`,
and `br_if` instead of `if`/`else` (equivalent, and slightly simpler to step
through). Read the whole file; this section explains its strategy rather than
every line.

**The invariant lives at an explicit machine state.** You cannot prove a loop
by stepping through it, because you do not know how many iterations there are.
Instead the file defines `factorialLoopConfig x acc`: the machine state at the
*top* of the loop, with counter `x` and accumulator `acc`, control frame and
all. This is the loop invariant, expressed as a `Config` rather than a
proposition.

**One iteration is a lemma.** `factorialLoop_iteration_steps x acc (hx : x ≠ 0)`
proves that from `factorialLoopConfig x acc` the machine takes exactly 13 steps
and arrives at `factorialLoopConfig (x - 1) (acc * x)`. The proof is a
`wasm_steps` call listing all 13 rules, including `.brIfZero` (the `br_if` that
does not branch) and `.br rfl` (the back-edge). The `(.eqz (result := 0) (by
simp [hx]))` piece names the rule's implicit argument and proves the side
condition with `simp` using the hypothesis.

**Exiting is a lemma.** `factorialLoop_zero_steps acc` proves that from
`factorialLoopConfig 0 acc` the machine takes 7 steps and finishes with
`done [acc]`. The `.brIf (by decide) (by rfl)` is the branch that *does* fire,
then `.exitControl` pops the block frame, then the trailing `local.get 1` and
`finish`.

**Induction stitches iterations together.** `factorialLoop_steps x acc` proves
that from the loop head with any `x` and `acc`, some trace reaches
`done [acc * x!]`. It uses `Nat.strong_induction_on` on `x.toNat`: assume the
claim for all smaller counters, then split on whether `x = 0`. In the zero case,
use the exit lemma. Otherwise, use the iteration lemma to get to
`factorialLoopConfig (x - 1) (acc * x)`, apply the induction hypothesis there
(the counter is smaller, which `omega` confirms after a lemma about `UInt32`
subtraction), and glue the two traces with `Steps.trans`. The arithmetic in the
middle (`hvalue`) shows `(acc * x) * (x - 1)! = acc * x!` at the `UInt32`
level, using `Nat.factorial_succ` from Mathlib.

**Entry is three steps.** `factorial_initial_steps n` proves the prelude
(`const 1`, `localSet 1`, `loop`) takes the function-entry config to the loop
head with `acc = 1`.

**Compose and lift.** `factorial_steps n` glues entry and loop. `factorial_terminates`
unpacks that into `TerminatesWith`, and `factorial_partial` is one line.

The lesson generalises: to prove a loop, (1) write the config at the loop
head as a function of the loop variables, (2) prove one iteration moves from
head to head with updated variables, (3) prove the exit case, (4) induct on a
measure that decreases each iteration. `SimpleLoop.lean` and `Gcd.lean` use
the same recipe.

## The tactics and lemmas you will actually meet

Tactics, in rough order of frequency in `Examples/`:

| Tactic | What it does |
|--------|--------------|
| `wasm_steps [r₁, r₂, ...]` | Apply `Steps.cons rᵢ` for each listed `Step` rule. Talos-specific. |
| `exact t` | The term `t` is the entire remaining proof. |
| `rfl` | Close a goal `a = b` where both sides compute to the same thing. |
| `decide +kernel` | Evaluate a concrete decidable claim in the kernel. Use for concrete-input checks. |
| `simp [f, h, lemma]` | Rewrite the goal using the given definitions, hypotheses, and lemmas plus the default simp set. |
| `simpa using h` | `simp` the goal and `h`, then close the goal with `h`. |
| `by_cases h : p` | Split into two goals: one assuming `p`, one assuming `¬p`. |
| `omega` | Decide linear arithmetic over `Nat` and `Int`. Often used after converting `UInt32` facts to `Nat`. |
| `obtain ⟨a, b⟩ := h` | Destructure an existential or a pair `h` into its parts. |
| `induction ... using Nat.strong_induction_on` | Strong induction: assume the claim for all smaller values. |
| `apply f` | Use `f`'s conclusion to close the goal, leaving its premises as new goals. |
| `intro x` | Move a `∀ x` or an implication's hypothesis into the context. |
| `have h : p := proof` | Prove a sub-fact and name it. |
| `rw [h]` | Rewrite the goal using equation `h` left-to-right. |
| `subst x` | Replace a variable by what an equation says it equals. |
| `<;>` | Run the following tactic on every goal the previous one produced. |
| `all_goals t` | Run `t` on every open goal. |

Lemmas that lift between layers (all in `SmallStep.lean`):

| Lemma | From | To |
|-------|------|----|
| `Steps.single`, `Steps.cons`, `Steps.refl`, `Steps.trans` | individual `Step`s | a `Steps` trace |
| `runSteps_eq_success_of_steps` | `Steps ... ⟨.done vs, st⟩` | `(runSteps n c).result = .success vs st` |
| `runSteps_finalConfig_of_steps` | any terminal `Steps` | the corresponding `runSteps` result |
| `runSteps_values_terminates` | `(runSteps n c).result.values? = some vs` | `TerminatesWith c (fun values _ => values = vs)` |
| `runSteps_values_partiallyMeets` | same | `PartiallyMeets ...` |
| `runSteps_trapped_trapsWith`, `..._store` | `(runSteps n c).result = .trapped r st` | `TrapsWith c r ...` |
| `TerminatesWith.of_steps` | `Steps ... ⟨.done vs, st⟩` and `post vs st` | `TerminatesWith c post` |
| `TerminatesWith.toPartiallyMeets` | total | partial |
| `TerminatesWith.mono` | `TerminatesWith c post` and `post → post'` | `TerminatesWith c post'` |

## Finding the rule for an instruction

`Step` has one constructor per instruction, plus administrative ones. To find
the rule for, say, `i32.rem_u`, search `SmallStep.lean` for `| remU`. The
constructor's arguments are its side conditions; if it takes an `(h : ...)`,
you must supply a proof, usually `rfl`, `by decide`, or a hypothesis of the
theorem.

The examples give you a working vocabulary fast. `grep -h "wasm_steps"
Interpreter/Wasm/Examples/*.lean` lists every rule name in use.

## Exploring a proof yourself

- **Put the cursor in the `by` block.** The infoview shows hypotheses and goal.
  Move down one line at a time.
- **`#check name`** in a scratch line shows a definition's type. Try
  `#check @runSteps_eq_success_of_steps`.
- **`#print name`** shows the definition or the proof term.
- **`#print axioms name`** lists the axioms a theorem depends on. For a Talos
  theorem you should see only the standard three (`propext`, `Classical.choice`,
  `Quot.sound`) or fewer. Seeing `Lean.ofReduceBool` means `native_decide` is
  in the chain, which new code must avoid.
- **Hover** over any identifier for its docstring. Most definitions in Talos
  have one.
- **Go to definition** (F12 in VS Code) jumps into `SmallStep.lean` or Mathlib.
  Do this on `wasm_steps` and on a `Step` constructor.

## Where to go next

You can now read any file under `Examples/`. The
[first contribution](04-first-contribution.md) guide explains how to turn that
into a change the maintainers will merge.
