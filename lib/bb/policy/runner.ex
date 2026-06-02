# SPDX-FileCopyrightText: 2026 Edgar Gomes de Araujo <talktoedgar@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Policy.Runner do
  @moduledoc """
  Executes a `BB.Policy` in a fixed-rate control loop.

  The runner is a `GenServer` that, on each tick, drives the policy cycle and
  applies the result to the robot's actuators — subject to the safety system:

      observe/3  →  act/2  →  action_to_commands/3  →  (safety check)  →  apply

  It owns:

    * **Observation collection** — reads robot state and the latest sensor
      payloads and hands them to the policy's `c:BB.Policy.observe/3`.
    * **Inference scheduling** — ticks at `:rate_hz`, rescheduled per tick via
      `Process.send_after/3` (the ecosystem idiom; see `BB.PID.Controller`).
    * **Action application** — applies commands via `BB.Actuator`, but only
      while `BB.Safety.armed?/1` is true. A disarm halts the episode.
    * **Episode lifecycle** — calls `c:BB.Policy.reset/1` at episode start and
      terminates on completion, timeout, safety intervention, or cancellation.
    * **Telemetry** — emits `[:bb, :policy, ...]` events (see `BB.Policy.Telemetry`).

  ## Entry point

  Use `run/4` for an episodic task that runs to completion or timeout:

      {:ok, result} =
        BB.Policy.Runner.run(MyRobot, BB.Policy.ONNX, %{task: :pick_mug},
          policy_opts: [
            model: "priv/models/pick_mug.onnx",
            normalizer: "priv/models/pick_mug.json",
            observation_keys: [:joint_positions, :joint_velocities],
            action_keys: [:target_positions]
          ],
          rate_hz: 20,
          timeout: :timer.seconds(30)
        )

  > #### Public API note {: .info}
  >
  > The proposal also describes `BB.Motion.run_policy/4`. `BB.Motion` lives in
  > the `bb` core package and has no extension hook for satellites, so that
  > convenience delegate must land via a PR to core. Until then, call
  > `BB.Policy.Runner.run/4` (or the `BB.Policy.run/4` facade) directly.

  ## Options

    * `:rate_hz` — control-loop frequency. Default `20`.
    * `:timeout` — maximum episode duration in ms. Default `30_000`.
    * `:policy_opts` — keyword list passed to `c:BB.Policy.init/1`.
    * `:goal` — goal specification forwarded to the policy.
  """

  use GenServer

  alias BB.Process, as: BBProcess

  @default_rate_hz 20
  @default_timeout :timer.seconds(30)

  @type goal :: term()
  @type result :: term()

  defstruct [
    :robot,
    :policy_module,
    :policy_state,
    :goal,
    :rate_hz,
    :timeout,
    :deadline,
    :tick_ref,
    episode_step: 0
  ]

  @typedoc false
  @type t :: %__MODULE__{}

  @doc """
  Start a runner under a supervisor, registered per-robot.

  Prefer `run/4` for one-shot episodic execution; use `start_link/1` when you
  want to supervise a long-lived policy process yourself.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    robot = Keyword.fetch!(opts, :robot)
    GenServer.start_link(__MODULE__, opts, name: BBProcess.via(robot, :policy_runner))
  end

  @doc """
  Run a policy on `robot` until completion, timeout, or safety intervention.

  Blocks the caller until the episode finishes and returns the policy's result.
  See the moduledoc for options.
  """
  @spec run(robot :: module(), policy :: module(), goal(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def run(robot, policy_module, goal, opts \\ []) do
    # TODO(phase: vertical-slice): start a (possibly transient) runner, await
    # the episode result, and tear it down. Pulls together start_link/1 +
    # the tick loop + a blocking await akin to BB.Command.await/2.
    _ = {robot, policy_module, goal, opts}
    {:error, :not_implemented}
  end

  @impl GenServer
  def init(opts) do
    robot = Keyword.fetch!(opts, :robot)
    policy_module = Keyword.fetch!(opts, :policy)

    state = %__MODULE__{
      robot: robot,
      policy_module: policy_module,
      goal: Keyword.get(opts, :goal),
      rate_hz: Keyword.get(opts, :rate_hz, @default_rate_hz),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }

    # TODO(phase: vertical-slice):
    #   * policy_module.init(policy_opts) -> policy_state (or {:stop, reason})
    #   * policy_module.reset/1 to start a clean episode
    #   * compute deadline from timeout
    #   * subscribe to sensor topics OR plan to poll BB.Robot.Runtime each tick
    #   * schedule first tick
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:tick, %__MODULE__{} = state) do
    # TODO(phase: vertical-slice): the loop body.
    #
    #   1. Deadline check -> {:stop, :timeout} when exceeded.
    #   2. BB.Safety.armed?/1 — if not armed, halt the episode (a disarm
    #      mid-episode is a safety intervention, not an error to retry).
    #   3. robot_state = BB.Robot.Runtime.get_robot_state(state.robot)
    #      sensors     = latest sensor payloads
    #   4. {obs, ps}      = policy_module.observe(robot_state, sensors, ps)
    #      {action, ps}   = policy_module.act(obs, ps)
    #      {:ok, cmds}    = policy_module.action_to_commands(action, robot, ps)
    #   5. Apply cmds via BB.Actuator (only while armed).
    #   6. Emit telemetry (inference time, step count).
    #   7. Reschedule the next tick.
    {:noreply, reschedule_tick(state)}
  end

  defp reschedule_tick(%__MODULE__{rate_hz: rate_hz} = state) do
    interval_ms = max(1, div(1000, rate_hz))
    %{state | tick_ref: Process.send_after(self(), :tick, interval_ms)}
  end
end
