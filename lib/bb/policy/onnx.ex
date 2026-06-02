# SPDX-FileCopyrightText: 2026 Edgar Gomes de Araujo <talktoedgar@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Policy.ONNX do
  @moduledoc """
  `BB.Policy` implementation that loads ONNX models via [Ortex](https://github.com/elixir-nx/ortex).

  This is the recommended way to deploy policies trained in Python (PyTorch,
  JAX, TensorFlow) on Beam Bots. The model is loaded once in `c:BB.Policy.init/1`
  and inference runs on each control tick.

  ## Usage

      {:ok, result} =
        BB.Policy.Runner.run(MyRobot, BB.Policy.ONNX, %{task: :pick_mug},
          policy_opts: [
            model: "priv/models/pick_mug.onnx",
            normalizer: "priv/models/pick_mug.json",
            observation_keys: [:joint_positions, :joint_velocities, :gripper],
            action_keys: [:target_positions, :target_gripper]
          ],
          rate_hz: 20
        )

  ## Inference: `Ortex.run/2`, not batched serving

  For a single robot at a fixed control rate, inference is one call at a time.
  This implementation calls `Ortex.run/2` directly. `Nx.Serving` batched
  execution exists to amortise overhead across *concurrent* requests; a single
  20 Hz loop never fills a batch, and `batch_timeout` would only add latency.
  Batched serving is reserved for a future multi-camera/multi-policy path.

  ## Exporting from LeRobot — read this before assuming it "just works"

  There is no first-class one-line ONNX export in LeRobot. In particular:

    * `policy.select_action` contains Python control flow (the action-chunk
      queue, temporal ensembling) that is **not traceable** — you export
      inference-only subgraphs wrapped in thin `nn.Module`s, often splitting
      vision encoder and transformer into separate graphs with static shapes.
    * **Normalisation is stripped from the graph.** Export the dataset
      statistics separately and apply them with `BB.Policy.Normalizer`.
    * **Diffusion / VLA (π0) policies** have iterative denoising loops that do
      not export cleanly today; target **ACT first**.

  ## Action chunking (ACT)

  ACT predicts a horizon of future actions per inference. Two runtime regimes:

    * **Receding-horizon queue** — execute queued actions one per tick; infer
      only when the queue empties. Cheaper; the recommended first implementation.
    * **Temporal ensembling** — infer every tick and blend overlapping chunks.
      Smoother but more compute.

  The chosen regime lives in this module's policy `state` (the queue/buffer);
  `BB.Policy.Runner` ticks at a fixed rate and asks for the action of the
  current step.

  > #### Status {: .info}
  >
  > Stub. Implemented in the `ortex-dev-box` phase (dev/sim target first; the
  > Nerves/aarch64 `libonnxruntime` story is a later, explicitly-scoped phase).
  > `ortex` is an optional dependency — this module only loads if it is present.
  """

  @behaviour BB.Policy

  defstruct [
    :model,
    :normalizer,
    :observation_keys,
    :action_keys,
    :action_chunk,
    :hidden_state
  ]

  @type t :: %__MODULE__{}

  @impl BB.Policy
  def init(opts) do
    _ = Keyword.fetch!(opts, :model)
    # TODO(phase: ortex-dev-box):
    #   model      = Ortex.load(model_path, execution_providers(opts))
    #   normalizer = BB.Policy.Normalizer.load(opts[:normalizer])
    #   verify ortex is loaded (Code.ensure_loaded?/1) and surface a clear
    #   error if the optional dep is missing.
    {:error, :not_implemented}
  end

  @impl BB.Policy
  def reset(%__MODULE__{} = state) do
    %{state | hidden_state: nil, action_chunk: nil}
  end

  @impl BB.Policy
  def observe(_robot_state, _sensors, %__MODULE__{} = state) do
    # TODO(phase: ortex-dev-box): gather observation_keys, normalise, return tensors.
    raise "not implemented"
    {%{}, state}
  end

  @impl BB.Policy
  def act(_observation, %__MODULE__{} = state) do
    # TODO(phase: ortex-dev-box): build input tuple, Ortex.run/2, slice the
    # action chunk, manage the receding-horizon queue in state.
    raise "not implemented"
    {%{}, state}
  end

  @impl BB.Policy
  def action_to_commands(_action, _robot, %__MODULE__{} = _state) do
    # TODO(phase: ortex-dev-box): denormalise via BB.Policy.Normalizer and
    # build BB.Actuator commands for the action_keys.
    {:error, :not_implemented}
  end
end
