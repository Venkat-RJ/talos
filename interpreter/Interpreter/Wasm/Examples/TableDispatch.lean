import Interpreter.Wasm.SmallStep
import Interpreter.Wasm.Examples.Harness

kernel_decoder

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

/-! ## Example: table inspection and decoded indirect dispatch

The symbolic probe frames an arbitrary physical store with a known table.
Decoded checks cover table size/get/null testing and indirect dispatch through
the same authoritative table representation.
-/

namespace Wasm
open SmallStep

def TableProbe : Program := [
  .const 2, .tableGet 0, .refIsNull, .tableSize 0
]

def tableProbeConfig (m : Module) (st : Store Unit) : Config Unit :=
  { expr := .running
      { locals := {}
        code := TableProbe
        resultArity := 2
        callerRemainder := [] }
    store := { runtime := { instances := #[{ module := m, host := {} }], entry := ⟨0⟩ }, wasm := st } }

theorem tableProbe_steps (m : Module) (st : Store Unit)
    (htbl :
      st.tables =
        [[.funcref (some 0), .funcref (some 1), .funcref none]])
    (h64 : m.tableIs64 0 = false) :
    Steps (tableProbeConfig m st)
      [(.instruction (.const 2)), (.instruction (.tableGet 0)),
       (.instruction .refIsNull), (.instruction (.tableSize 0)),
       (.administrative .finish)]
      ⟨.done [.i32 3, .i32 1], (tableProbeConfig m st).store⟩ := by
  apply Steps.cons .const
  apply Steps.cons (.tableGet
    (table := [.funcref (some 0), .funcref (some 1), .funcref none])
    (value := .funcref none) rfl (by simp [htbl]) rfl)
  apply Steps.cons (.refIsNullTrue rfl)
  apply Steps.cons (.tableSize
    (table := [.funcref (some 0), .funcref (some 1), .funcref none])
    (by simp [htbl]))
  apply Steps.cons .finish
  simpa [tableProbeConfig, h64, sizeValue,
         RuntimeEnv.currentModule, RuntimeEnv.currentInstance] using
    (Steps.refl
      (⟨.done [.i32 3, .i32 1],
        (tableProbeConfig m st).store⟩ : Config Unit))

theorem tableProbe_terminates (m : Module) (st : Store Unit)
    (htbl :
      st.tables =
        [[.funcref (some 0), .funcref (some 1), .funcref none]])
    (h64 : m.tableIs64 0 = false) :
    TerminatesWith (tableProbeConfig m st)
      (fun values store =>
        values = [.i32 3, .i32 1] ∧ store.wasm = st) := by
  refine ⟨_, _, _, tableProbe_steps m st htbl h64, rfl, rfl⟩

namespace Decoded

def dispatchWat : String := "
(module
  (type $sig (func (result i32)))
  (func $f0 (result i32) i32.const 10)
  (func $f1 (result i32) i32.const 20)
  (table 3 funcref)
  (elem (i32.const 0) $f0 $f1)
  (func $sz (export \"sz\") (result i32)
    table.size)
  (func $is_null (export \"is_null\") (param i32) (result i32)
    local.get 0
    table.get
    ref.is_null)
  (func $dispatch (export \"dispatch\") (param i32) (result i32)
    local.get 0
    call_indirect (type $sig)))
"

private def decoded : Wasm.Module := Wasm.Examples.decodeOrDefault dispatchWat

private def decodedConfig (index : Nat)
    (args : List Value) : Config Unit :=
  { expr := .running
      { locals := decoded.funcs[index]!.toLocals args.reverse
        code := decoded.funcs[index]!.body
        resultArity := decoded.funcs[index]!.results.length
        callerRemainder := [] }
    store :=
      { runtime := { instances := #[{ module := decoded, host := {} }], entry := ⟨0⟩ }
        wasm := decoded.initialStore } }

private def runVals (index : Nat)
    (args : List Value) : Option (List Value) :=
  (runSteps 20 (decodedConfig index args)).result.values?

theorem decodes_five_funcs : decoded.funcs.length = 5 := by cbv

theorem table_populated :
    (decoded.initialStore (α := Unit)).tables =
      [[.funcref (some 0), .funcref (some 1), .funcref none]] := by cbv

theorem sz_runs : runVals 2 [] = some [.i32 3] := by cbv

theorem is_null_slot0_runs :
    runVals 3 [.i32 0] = some [.i32 0] := by cbv

theorem is_null_slot2_runs :
    runVals 3 [.i32 2] = some [.i32 1] := by cbv

theorem dispatch_slot0_runs :
    runVals 4 [.i32 0] = some [.i32 10] := by cbv

theorem dispatch_slot1_runs :
    runVals 4 [.i32 1] = some [.i32 20] := by cbv

theorem dispatch_slot0_terminates :
    TerminatesWith (decodedConfig 4 [.i32 0])
      (fun values _ => values = [.i32 10]) :=
  runSteps_values_terminates dispatch_slot0_runs

end Decoded

/-! ### Table initializer expressions

`(table N elemtype (expr))` fills every slot at instantiation. The pass runs
with the other constant-expression passes (`Module.runTableInits`, after
`runConstGlobals`); a literal `ref.func` fills the table, and an active segment
already written by `initialStore` stays on top of the fill. -/

namespace TableInit

def literalModule : Module :=
  { funcs := [{ body := [] }, { body := [] }]
    tables := [{ min := 3, init := [.refFunc 0] }]
    elements := [{ tableIdx := some 0, offset := some 1, funcs := [some 1] }] }

theorem literal_fill :
    (literalModule.runTableInits 10 (literalModule.initialStore (α := Unit))).tables =
      [[.funcref (some 0), .funcref (some 1), .funcref (some 0)]] := by decide +kernel

/- A `global.get` initializer goes through `exec`, which the kernel cannot
reduce on a store, so that path is pinned by the spec rows instead
(`table.wast:93`, tables `$t4` / `$t5`). -/

/-! The text format allows the initializer folded, as source files write it,
or unfolded, as `wasm-tools print` emits it; both decode to the same `init`. -/

private def foldedWat : String :=
  "(module (func) (table 3 funcref (ref.func 0)))"

private def unfoldedWat : String :=
  "(module (func) (table (;0;) 3 (ref func) ref.func 0))"

theorem folded_decodes :
    (Wasm.Examples.decodeOrDefault foldedWat).tables.map (·.init) = [[.refFunc 0]] := by
  cbv

theorem unfolded_decodes :
    (Wasm.Examples.decodeOrDefault unfoldedWat).tables.map (·.init) = [[.refFunc 0]] := by
  cbv

theorem plain_table_has_no_init :
    (Wasm.Examples.decodeOrDefault "(module (table 3 5 funcref))").tables.map
      (fun t => (t.min, t.max, t.init)) = [(3, some 5, [])] := by
  cbv

end TableInit
end Wasm
