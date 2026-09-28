# How to make your first contribution to Talos

You will pick a task that fits your current skills, make the change on a branch
of your fork, verify it the way CI will, and open a pull request that the
maintainers can review quickly. This guide complements
[`CONTRIBUTING.md`](../../CONTRIBUTING.md), which states the project's
guidelines; here the focus is on the concrete steps and the mistakes newcomers
make.

## Prerequisites

- A working build of at least the `interpreter/` package
  ([Getting started](02-getting-started.md)).
- A GitHub account and a fork of `cajal-technologies/talos`.
- Optionally, join the Telegram channel linked from the README. Asking "is
  anyone working on X?" before you start saves everyone time.

## Step 1: Pick a task that matches where you are

The maintainers list good directions in `CONTRIBUTING.md`. Here they are again
with an honest read on what each demands of a newcomer.

| Task | Lean needed | Extra tools | Good first task? |
|------|-------------|-------------|------------------|
| Fix or improve documentation | none | none | Yes. Docs that were wrong or confusing when you onboarded are the clearest signal you can give. |
| Improve error messages, `just` recipes, CI feedback | little | maybe `just` | Yes. See the "Quality-of-life" bullet in CONTRIBUTING. |
| Write a missing example in `interpreter/Interpreter/Wasm/Examples/` | the [reading a proof](03-reading-a-proof.md) guide | none | Yes, once you have done the Getting started tutorial. Pick an instruction or control pattern no example covers yet. |
| Find an interpreter bug by writing an example whose proof fails unexpectedly | same | none | Yes. Report it with the minimal file even if you cannot fix it. |
| Extend spec testsuite coverage | moderate | `just`, `wasm-tools` at the pinned version | After a few examples. Currently the report shows zero `fail` and zero `interpreter_error` rows, so remaining work is in the `skipped` buckets and in the open GitHub issues. |
| Add a lemma to `codelib/` | comfortable with Lean | none | Later. A lemma is accepted only with a real consumer. |
| Add a Rust crate to `programs/` with a proved spec | comfortable with Lean, some Rust | Rust toolchain, `wasm-tools`, `just` | Later. Open an issue describing the crate and property first; the maintainers ask for this. |

Check the open issues on GitHub as well. The repository has a `good first
issue` label; at the time of writing no open issue carries it, so ask on
Telegram if you want a pointer.

## Step 2: Branch from an up-to-date `main`

```bash
git remote add upstream https://github.com/cajal-technologies/talos.git   # once
git fetch upstream
git checkout -b <short-branch-name> upstream/main
```

Use a branch name that says what the change is (`docs/onboarding-guide`,
`examples/rotl-rotr`).

## Step 3: Make the change, following the house rules

These rules are load-bearing. Reviewers will ask for them, and CI enforces
several.

**Kernel-checked proofs only.** Do not use `native_decide`, `bv_decide`, or
`bv_check` in new or rewritten proofs. Use `decide +kernel` for concrete
evaluation and ordinary tactics otherwise. Check with `#print axioms
yourTheorem`: seeing `Lean.ofReduceBool` means a native tactic slipped in.
Existing uses are legacy, not precedent.

**Never mention fuel in a specification.** `runSteps 5 ...` belongs inside a
proof, never in a theorem that is meant as a public statement. Public
statements use `TerminatesWith`, `PartiallyMeets`, and `TrapsWith`.

**Register new examples.** Every file under `Interpreter/Wasm/Examples/` must
be imported from `Interpreter/Wasm/Examples/Basic.lean`. That umbrella file is
the only thing the CI build reaches; an unregistered example is never compiled.

**Follow the theorem naming convention.** `<name>_steps`, `<name>_runs`,
`<name>_terminates`, `<name>_partial`, `<name>_traps`. Look at a recent example
for the current shape.

**Keep the interpreter simple.** If you touch `SmallStep.lean` or
`Semantics.lean`, prefer the formulation that is easiest to unfold in a proof
over the one that runs faster. The structure of `Config`, `Step`, and
`runSteps` is depended on by every proof in the repository: extend in place,
keep new cases consistent with existing ones, and expect to update both the
relational `Step` constructor and the executable `stepChecked?` plus the
soundness and completeness proofs that connect them.

**One logical change per PR.** A new example, or a bug fix, or a doc change.
Not all three.

**Regenerate `testsuite_report.txt` if coverage moves.** If your change turns a
`skipped` or `fail` row into `pass` (or the reverse), run `just
testsuite-report` with the pinned `wasm-tools` version and commit the result.
CI fails otherwise. Documentation and example changes do not affect it.

**Codelib lemmas need a consumer.** A lemma with no use site will not be
accepted.

**Disclose AI assistance.** If you used an AI tool to write or review code,
say so in the PR description. You are still accountable for every line.

**When guidance files disagree, the code wins.** `AGENTS.md` describes the
current post-migration rules (small-step machine is authoritative,
kernel-checked proofs). Some older text in `CLAUDE.md` and `docs/std_guide.md`
still describes the big-step `wp` API. Follow what the current examples do.

## Step 4: Verify the way CI will

Check a single file quickly while iterating:

```bash
cd interpreter
lake env lean Interpreter/Wasm/Examples/YourFile.lean
```

Before opening the PR, build the affected package with warnings as errors, the
same flag CI uses:

```bash
cd interpreter && lake build --wfail        # if you touched interpreter/
cd codelib     && lake build --wfail        # if you touched codelib/ (also rebuilds interpreter)
cd programs/lean && lake build --wfail      # if you touched programs/
```

`--wfail` turns warnings into errors. A leftover `sorry`, an unused variable, or
a deprecated lemma will fail here, so fix them locally.

Run the axiom audit if you touched proofs:

```bash
python3 scripts/axiom-audit.py interpreter --report /tmp/axioms.json
```

For documentation changes, check that every relative link resolves. A quick
way:

```bash
grep -oE '\]\([^)#]+' docs/onboarding/*.md | sed 's/.*](//' | sort -u
```

and confirm each path exists.

## Step 5: Commit with the project's message style

Look at `git log --oneline -20` on `main`. Titles are lowercase, imperative,
and usually prefixed with the area they touch:

```
codelib: bump iris-lean to upstream master 728a171
interpreter: normalise the example theorem naming convention
verifier: add semantic public specification interface
ci: remove verifier report preview workflow
```

Stage files by name (never `git add -A`), then:

```bash
git add docs/onboarding/01-concepts.md
git commit -m "docs: add onboarding guide for newcomers"
```

## Step 6: Open the pull request

```bash
git push -u origin <short-branch-name>
gh pr create --repo cajal-technologies/talos --base main
```

(Or use the GitHub web UI.) In the description, state:

- what changed and why, in two or three sentences;
- how you verified it (`lake build --wfail` in which package, `lake env lean`
  on which file, links checked);
- whether AI tooling was used;
- for examples: which instruction or pattern was previously uncovered.

PRs are squash-merged, so the PR title becomes the commit title on `main`.
Give it the same style as Step 5.

## What CI runs on your PR

Three workflows in `.github/workflows/`:

| Workflow | What it checks | Fails when |
|----------|----------------|------------|
| `lean_action_ci.yml`, job **Build CodeLib proofs** | `lake build --wfail` in `codelib/` (which builds the interpreter modules it imports), then the axiom audit over interpreter, codelib, and verifier. | Any proof fails, any warning, or a declaration depends on a disallowed axiom. |
| `lean_action_ci.yml`, jobs **Build program wasm** and **Build program proofs** | Compiles the Rust crates to wasm on Linux, then builds `programs/lean` with `--wfail` on macOS against those exact bytes, then audits its axioms. | A `Spec.lean` proof fails, a warning appears, or a generated `Program.lean` no longer matches its `.wat`. |
| `lean_action_ci.yml`, job **Smoke test** | Builds the full `Interpreter` library and the runner, then runs `just runner-smoke`. This is the only job that compiles `Examples/`, and it reaches an example only if `Examples/Basic.lean` imports it. | An example fails to check, or the runner misbehaves on `samples/`. |
| `testsuite-report.yml` | Regenerates `testsuite_report.txt` with the pinned `wasm-tools` and diffs it. | Your change shifted coverage and you did not commit the regenerated report. |
| `verifier-freshness.yml` | Re-runs `verifier check --no-prove` and diffs `programs/`. | You changed a Rust crate without re-emitting, or edited a generated file by hand. |

For a docs-only change, every job runs but nothing you touched is compiled.
For a new example, the **Smoke test** job is the one that checks it.

## Checklist before you click "Create pull request"

- [ ] Branch is based on current `upstream/main`.
- [ ] `lake build --wfail` passes in every package you touched.
- [ ] New example is imported from `Examples/Basic.lean`.
- [ ] No `native_decide` / `bv_decide` in new proofs; `#print axioms` is clean.
- [ ] Public theorems use `TerminatesWith` / `PartiallyMeets` / `TrapsWith`, no fuel.
- [ ] `testsuite_report.txt` regenerated if coverage moved.
- [ ] One logical change.
- [ ] Commit and PR titles follow `area: lowercase imperative summary`.
- [ ] PR description says how you verified and whether AI helped.
- [ ] Links in any Markdown you touched resolve.

## After you open it

Expect review comments. The maintainers are precise about proof style and
naming because every example is read by the next newcomer. Address each
comment with a follow-up commit (the squash merge collapses them). If a
reviewer asks for something you do not understand, ask; that is expected and
welcome.

## Where to go next

The [repository map](05-repo-map.md) is the reference you will keep open while
working: which file holds what, every `just` recipe, and the runner CLI.
