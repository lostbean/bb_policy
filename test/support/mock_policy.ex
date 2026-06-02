# SPDX-FileCopyrightText: 2026 Edgar Gomes de Araujo <talktoedgar@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Policy.Support.MockPolicy do
  @moduledoc """
  A trivial, dependency-free `BB.Policy` for tests.

  It carries a step counter in its state, "observes" nothing, and "acts" by
  echoing a constant action. Use it to exercise `BB.Policy.Runner` lifecycle
  and the behaviour contract without Ortex or a real model.
  """

  @behaviour BB.Policy

  @impl BB.Policy
  def init(opts), do: {:ok, %{steps: 0, opts: opts}}

  @impl BB.Policy
  def reset(state), do: %{state | steps: 0}

  @impl BB.Policy
  def observe(_robot_state, _sensors, state) do
    {%{noop: Nx.tensor([0.0])}, %{state | steps: state.steps + 1}}
  end

  @impl BB.Policy
  def act(_observation, state) do
    {%{target_positions: Nx.tensor([0.0])}, state}
  end

  @impl BB.Policy
  def action_to_commands(_action, _robot, _state), do: {:ok, []}

  @impl BB.Policy
  def info(state), do: %{architecture: :mock, steps: state.steps}
end
