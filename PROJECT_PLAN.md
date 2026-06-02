<!--
SPDX-FileCopyrightText: 2026 Edgar Gomes de Araujo <talktoedgar@gmail.com>

SPDX-License-Identifier: Apache-2.0
-->

# bb_policy — Project Plan

Roadmap and design decisions for `bb_policy`, the learned-policy package for
Beam Bots. The authoritative requirements are the accepted proposal
[`0002-bb-policy.md`](https://github.com/beam-bots/proposals/blob/main/accepted/0002-bb-policy.md);
this document records *how* we build it, the decisions where we diverge from the
proposal, and the risks surfaced by an ecosystem + ML-stack review.

## 1. Where this sits

`bb_policy` is a **satellite** of `bb` core (currently `0.20.x`, Elixir `~> 1.19`,
OTP 28). It depends on the public APIs of core and adds nothing to core itself.
It is the runtime that executes policies trained elsewhere — training, datasets,
teleop, and vision live in their own packages.

```
                bb (core: DSL, Robot, Runtime, Safety, Actuator, PubSub, Telemetry)
                          ▲
        ┌─────────────────┼─────────────────┐
   bb_pid_controller   bb_policy   bb_ik_fabrik   …   (satellites)
        (this package) ─┘
                          │ optional
                        ortex → onnxruntime
```

## 2. Key decisions

### D1 — Public entry point is `BB.Policy.run/4`; `BB.Motion.run_policy/4` is a deferred core PR

The proposal shows `BB.Motion.run_policy/4`. `BB.Motion` lives in **core** and
exposes no extension/registration hook for satellites, so a satellite cannot add
a function to it. We ship the public API as **`BB.Policy.run/4`** (a thin
delegate to `BB.Policy.Runner.run/4`). Adding the `BB.Motion.run_policy/4`
convenience delegate is tracked as a **separate PR to `bb` core** and is not a
blocker for this package.

### D2 — Runner is a standalone `GenServer` first; `BB.Controller` integration is additive later

The proposal models the runner as a plain `GenServer` with `run/4`. The
ecosystem idiom for *long-lived, declaratively-configured* loops is
`use BB.Controller` (as `BB.PID.Controller` does), which buys supervision,
runtime parameters, and a safety `disarm/1` callback for free.

We do **both, in order**: ship the standalone `GenServer` + `run/4` first
(matches the proposal and the episodic "run a task to completion" use case),
then add a `BB.Controller`-based path for policies that should live in the robot
DSL as a continuously-running controller. The control-loop body (observe → act →
commands → safety → apply) is shared between them.

### D3 — Inference via `Ortex.run/2`, not `Nx.Serving` batched execution

A single robot at a fixed rate issues one inference at a time. `Nx.Serving`'s
batched execution exists to amortise overhead across *concurrent* requests; here
it never fills a batch and its `batch_timeout` (default 100 ms) only adds
latency. Call `Ortex.run/2` directly. Batched serving is reserved for a future
multi-camera / multi-policy scenario.

### D4 — Normalisation is owned by the runtime, not the model

LeRobot (and similar) strip input/output normalisation out of the exported ONNX
graph and ship the dataset statistics separately. `BB.Policy.Normalizer` applies
them at inference time (`:min_max`, `:z_score`, `:identity`). The ONNX file is
**not** assumed to be end-to-end.

### D5 — Target ACT first; first inference on a dev box / simulator

ACT (action-chunking transformer) is small, fast, and the realistic ONNX export
path. Diffusion and VLA (π0) policies have iterative loops that do not export
cleanly today — they are deferred and explicitly out of v1 scope. The first
*real* ONNX inference targets an x86/Mac dev box against a simulated robot; the
Nerves/aarch64 deployment story (the biggest integration risk, see R1) is a
later, separately-scoped phase.

### D6 — `ortex` is an optional dependency

The behaviour, runner, and normaliser have no ML runtime dependency. `ortex` is
`optional: true`; `BB.Policy.ONNX` guards on its presence and degrades to a
clear error when absent, so the package compiles and tests pass without a
compiled onnxruntime.

## 3. Risks (from the ML-stack review)

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | **Nerves/aarch64 deployment.** Ortex publishes no precompiled NIFs and pins `ort 2.0-rc`; you must cross-compile the Rustler NIF *and* supply an aarch64 `libonnxruntime` that ort can find. | High | Defer (D5). Spike separately: `load-dynamic` + `ORT_DYLIB_PATH` to a Pi onnxruntime build, or build from source. Treat as its own phase with its own acceptance test. |
| R2 | **LeRobot → ONNX export is not a one-liner.** `select_action` (action queue, ensembling) isn't traceable; export is inference-only subgraphs, often split (vision/transformer), static shapes, opset 11. | High | Owned by a PyTorch-side export pipeline, *out of this repo*. Document the contract (input/output signature + separate stats JSON) the runtime expects. Provide a known-good fixture model. |
| R3 | **NIF blocks the BEAM scheduler.** Ortex inference is a Rustler NIF; a multi-ms call on a normal scheduler hurts soft-real-time jitter. | Medium | Verify Ortex uses a dirty NIF; isolate inference in its own process from the timing loop; cap onnxruntime's intra/inter-op thread pool (leave headroom for BEAM schedulers). Measure **p99**, not mean. |
| R4 | **Silent CPU fallback.** ort silently falls back to CPU if a requested execution provider isn't compiled in. | Low | Log/assert the active EP at load; document that CUDA/CoreML require building Ortex with those features. |
| R5 | **Diffusion/VLA expectations.** Users may expect any LeRobot policy to "just load". | Low | Scope doc + clear error: v1 supports ACT-class static-shape ONNX. |

## 4. Phased roadmap

Each phase is a vertical slice that leaves the tree green (`mix check`).

### Phase 0 — Scaffold ✅ (this commit)

- Ecosystem-standard project: `mix.exs`, `.check.exs`, `.formatter.exs`,
  `.tool-versions`, `renovate.json`, CI workflow, `LICENSES/` + SPDX headers,
  `AGENTS.md`/`CLAUDE.md`, `CHANGELOG.md`.
- `BB.Policy` behaviour (full callback contract + typedocs).
- Stubs with typed signatures + phase-tagged TODOs: `Runner`, `Normalizer`,
  `ONNX`, `Telemetry`; `BB.Policy.run/4` facade.
- `MockPolicy` test support + behaviour-contract tests.

### Phase 1 — Normalizer (no robot, no ML) ✅

- `:z_score`, `:min_max` (`[0,1]` and `[-1,1]`), `:identity` via `normalize/4` /
  `denormalize/4`, keyed per `:observation`/`:action` space with **per-key**
  strategy; scalar and per-element (tensor) moments; exact round-trip.
- Numerical safety: zero std / `min == max` treated as unit scale (no NaN/Inf).
- `new/1` (+ `new!/1`) validation, `stats_from_samples/3`, and `load/1` parsing
  the exported stats JSON via the stdlib `JSON` module (no extra dependency).
- **Done:** 22 tests + 2 doctests green; `mix format` and `credo --strict` clean.

### Phase 2 — Runner vertical slice (MockPolicy) ✅

- `Runner.init/1` (policy init + reset, deadline, first tick), the
  `handle_info(:tick, …)` loop, and `run/4` (start → monitor → await → teardown).
- Safety gate (`BB.Safety.armed?/1`) checked every tick; a disarm — at start or
  mid-episode — ends the episode with `:disarmed` (intervention, not a retry).
- Deadline/`:timeout`; policy-signalled completion (`act/2` → `{:done, state}`);
  action-conversion errors surfaced as `{:error, {:action_conversion, _}}`.
- Reads robot state via `BB.Robot.Runtime.get_robot_state/1`; applies
  `BB.Policy.ActuatorCommand`s via `BB.Actuator` (new `ActuatorCommand` struct +
  dispatcher, since core has no command type).
- Episode + per-tick inference telemetry (`BB.Policy.Telemetry`).
- **Done:** 14 runner/command tests cover completion, timeout, disarm (both
  forms), init error, conversion error, command application/gating, and
  telemetry. Full suite (38 tests + 2 doctests) green; format, `credo --strict`
  (only phase TODO suggestions), and dialyzer clean.

  The bb boundary (`BB.Safety`, `BB.Robot.Runtime`, `BB.Actuator`) is stubbed
  with Mimic in global mode (the runner runs in its own process). A full
  `simulation: :kinematic` robot integration test is deferred to Phase 3, where
  a real ONNX policy gives it something meaningful to drive.

### Phase 3 — ONNX on dev box (D5) ✅

- `BB.Policy.ONNX` loads a model with `Ortex.load/2`, runs `Ortex.run/2` (direct,
  not batched — D3), wires in `BB.Policy.Normalizer`, and builds
  `BB.Policy.ActuatorCommand`s from the output via a declarative `:observation`
  (`source: joints`) / `:action` (`{joints, kind}`) spec.
- Action-chunking: receding-horizon queue — `act/2` pops one row; refills by
  inferring when the queue empties (a single-action model = infer every tick).
- Optional-dependency hygiene: `init/1` guards with `Code.ensure_loaded?(Ortex)`;
  the two Ortex calls use `apply/3` so the package compiles
  `--warnings-as-errors` and passes dialyzer **without** ortex present.
- Toolchain: `flake.nix` gained `rustc`/`cargo`; `ORTEX=1` builds the NIF and
  `ort`'s `download-binaries` fetches an `aarch64-apple-darwin` onnxruntime.
- Fixture: `test/fixtures/generate_linear.py` builds a tiny static-shape linear
  ONNX (committed as `linear_policy.onnx`); the integration test is tagged
  `:ortex` and auto-excluded when Ortex isn't loaded.
- **Done:** real onnxruntime inference verified end-to-end (obs → normalise →
  `Ortex.run` → denormalise → commands) with exact expected outputs. With
  `ORTEX=1`: 44 tests + 2 doctests green. Without: 38 tests (6 excluded),
  format / warnings-as-errors / `credo --strict` / dialyzer / `reuse lint` clean.

  Not yet done (deferred): driving a live `simulation: :kinematic` robot through
  `BB.Policy.Runner` with this policy (the runner + ONNX are each tested in
  isolation); temporal ensembling; multi-input models (e.g. vision + state).

### Phase 4 — Reactor command wrapper (proposal "Should Have")

- `BB.Policy.Command` usable as a `bb_reactor` step: callable as
  `robot.command(goal) → {:ok, pid}`, exits `:normal` on completion so the
  reactor's monitor resolves; safety disarm surfaces as `:halt`.

### Phase 5 — `BB.Controller` path (D2) + temporal ensembling

- `use BB.Controller` runner variant for DSL-declared, continuously-running
  policies, with a `disarm/1` that stops inference.
- Temporal-ensembling action-selection regime alongside the queue.

### Phase 6 — Nerves / aarch64 deployment (R1)

- Cross-compiled Ortex NIF + aarch64 `libonnxruntime`; documented deploy path;
  on-target latency/jitter (p99) measurements; thread-pool tuning (R3).
- Core PR for `BB.Motion.run_policy/4` (D1).

## 5. Acceptance-criteria → phase map

From the proposal's "Acceptance Criteria":

**Must Have** — behaviour (P0) · runner loop at configurable rate (P2) ·
normaliser min-max & z-score (P1) · ONNX via Ortex (P3) · `run_policy` entry
point (P0 as `BB.Policy.run/4`; core delegate P6) · safety integration (P2) ·
timeout handling (P2) · basic telemetry (P2) · ONNX export docs (P3) · tests for
contract/lifecycle/normalisation (P0–P2).

**Should Have** — `BB.Policy.Command` reactor wrapper (P4) · stats from JSON
(P1) · GPU/EP config (P3, dev box) · graceful inference-failure degradation
(P3) · episode reset (P2) · example on simulated robot (P3).

**Won't Have** (separate packages) — native Axon policies, diffusion policies,
training loops, dataset management, vision encoders, Python bridge.

## 6. Open questions (from the proposal) — current leanings

1. **Observation source** — pre-processed robot state from `BB.Robot.Runtime`
   plus latest sensor payloads; camera frames handled in `observe/3` for now,
   revisit if a `bb_vision` pipeline lands.
2. **Action representation** — configurable per policy via `action_keys`;
   target positions first, deltas/velocities as variants.
3. **Episode boundaries** — timeout + policy-signalled completion; external
   cancel via the runner process. (Needs a "done" signal in the action contract.)
4. **Goal specification** — opaque term forwarded into policy state; policies
   that condition on a goal map it into their observation.
5. **Multi-step actions (chunking)** — receding-horizon queue first (P3),
   temporal ensembling later (P5).
6. **Vision input** — preprocessing in `observe/3` initially.
7. **Recurrent policies** — hidden state lives in policy `state`; history-window
   buffering is the policy's concern.

These are tracked to be closed as the relevant phases land.
