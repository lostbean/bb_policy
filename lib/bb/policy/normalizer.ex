# SPDX-FileCopyrightText: 2026 Edgar Gomes de Araujo <talktoedgar@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Policy.Normalizer do
  @moduledoc """
  Observation and action normalisation.

  Policies expect normalised inputs and produce normalised outputs. The
  statistics used for normalisation are a property of the *training dataset*
  and must be applied identically at inference time — frameworks such as
  LeRobot strip normalisation out of the exported ONNX graph and ship the
  statistics separately, so the runtime owns this step.

  ## Strategies

    * `:min_max` — scale to `[0, 1]` (or `[-1, 1]`) using per-key `min`/`max`.
    * `:z_score` — standardise to mean `0`, std `1` using per-key `mean`/`std`.
    * `:identity` — passthrough (no statistics required).

  ## Statistics

  `t:stats/0` maps each observation/action key to the moments that strategy
  needs. Values may be scalars or `Nx.Tensor.t/0` (for per-element stats, e.g.
  per-joint or per-channel). Stats can be hardcoded, or loaded from the JSON a
  training pipeline exports alongside the model.

  > #### Status {: .info}
  >
  > This module is the first fully-implemented vertical slice. The function
  > bodies below are stubs to be filled in (red-green-refactor) in the
  > `vertical-slice` phase; the contract and types are stable.
  """

  defstruct observation_stats: %{}, action_stats: %{}, strategy: :identity

  @type strategy :: :min_max | :z_score | :identity

  @type key_stats :: %{
          optional(:mean) => float() | Nx.Tensor.t(),
          optional(:std) => float() | Nx.Tensor.t(),
          optional(:min) => float() | Nx.Tensor.t(),
          optional(:max) => float() | Nx.Tensor.t()
        }

  @type stats :: %{atom() => key_stats()}

  @type t :: %__MODULE__{
          observation_stats: stats(),
          action_stats: stats(),
          strategy: strategy()
        }

  @doc """
  Normalise `tensor` using the statistics registered for `key`.

  Used on the observation path (raw reading → policy input).
  """
  @spec normalize(Nx.Tensor.t(), stats(), atom()) :: Nx.Tensor.t()
  def normalize(_tensor, _stats, _key) do
    # TODO(phase: vertical-slice):
    #   :z_score  -> (x - mean) / std
    #   :min_max  -> (x - min) / (max - min)   [optionally rescale to [-1, 1]]
    #   :identity -> x
    raise "not implemented"
  end

  @doc """
  Invert `normalize/3`: map a normalised value back to engineering units.

  Used on the action path (policy output → actuator command).
  """
  @spec denormalize(Nx.Tensor.t(), stats(), atom()) :: Nx.Tensor.t()
  def denormalize(_tensor, _stats, _key) do
    # TODO(phase: vertical-slice): inverse of normalize/3 per strategy.
    raise "not implemented"
  end

  @doc """
  Load a normaliser from the JSON statistics file produced by a training export.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(_path) do
    # TODO(phase: vertical-slice): parse the exported stats JSON into %__MODULE__{}.
    {:error, :not_implemented}
  end
end
