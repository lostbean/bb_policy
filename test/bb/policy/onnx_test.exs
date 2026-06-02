# SPDX-FileCopyrightText: 2026 Edgar Gomes de Araujo <talktoedgar@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Policy.ONNXTest do
  # Requires the Ortex NIF (ORTEX=1 + a Rust toolchain). Skipped otherwise so
  # the suite stays green without onnxruntime.
  use ExUnit.Case, async: false

  use Mimic

  alias BB.Policy.ActuatorCommand
  alias BB.Policy.Normalizer
  alias BB.Policy.ONNX

  @moduletag :ortex
  @model "test/fixtures/linear_policy.onnx"

  setup :set_mimic_global

  # The fixture computes action = obs @ W + b with
  #   W = [[1,0],[0,2],[1,1]], b = [0.5, -0.5]
  # so obs [1,2,3] -> [1*1+2*0+3*1+0.5, 1*0+2*2+3*1-0.5] = [4.5, 6.5].
  @policy_opts [
    model: @model,
    observation: [positions: [:a, :b, :c]],
    action: [{[:x, :y], :position}]
  ]

  defp robot_state_with(positions) do
    stub(BB.Robot.State, :get_all_positions, fn _ -> positions end)
    %{}
  end

  describe "init/1" do
    test "loads the model and defaults the normaliser to identity" do
      assert {:ok, %ONNX{} = state} = ONNX.init(@policy_opts)
      assert %Normalizer{} = state.normalizer
      assert state.action_queue == []
    end

    test "errors on a missing required option" do
      assert {:error, {:missing_option, :model}} =
               ONNX.init(observation: [], action: [])
    end
  end

  describe "the full observe -> act -> action_to_commands cycle" do
    setup do
      {:ok, state} = ONNX.init(@policy_opts)
      %{state: state}
    end

    test "runs inference and produces the expected actuator commands", %{state: state} do
      robot_state = robot_state_with(%{a: 1.0, b: 2.0, c: 3.0})

      {observation, state} = ONNX.observe(robot_state, %{}, state)
      assert %{input: input} = observation
      assert Nx.to_flat_list(input) == [1.0, 2.0, 3.0]

      {action, state} = ONNX.act(observation, state)
      assert %{action: action_tensor} = action
      assert close?(action_tensor, [4.5, 6.5])

      assert {:ok, commands} = ONNX.action_to_commands(action, MyRobot, state)

      assert [
               %ActuatorCommand{path: :x, kind: :position, value: vx},
               %ActuatorCommand{path: :y, kind: :position, value: vy}
             ] = commands

      assert_in_delta vx, 4.5, 1.0e-5
      assert_in_delta vy, 6.5, 1.0e-5
    end

    test "missing joints read as 0.0", %{state: state} do
      robot_state = robot_state_with(%{a: 1.0})
      {%{input: input}, _state} = ONNX.observe(robot_state, %{}, state)
      assert Nx.to_flat_list(input) == [1.0, 0.0, 0.0]
    end
  end

  describe "normalisation integration" do
    test "denormalises actions back to engineering units" do
      # Action min_max [-10,10] -> the model output is in [0,1]-ish; here we just
      # check the denormalise path is wired: identity stats means passthrough,
      # z_score with mean/std shifts the output.
      {:ok, normalizer} =
        Normalizer.new(action: %{output: %{strategy: :z_score, mean: 1.0, std: 2.0}})

      opts = Keyword.put(@policy_opts, :normalizer, normalizer)
      {:ok, state} = ONNX.init(opts)
      robot_state = robot_state_with(%{a: 1.0, b: 2.0, c: 3.0})

      {observation, state} = ONNX.observe(robot_state, %{}, state)
      {action, state} = ONNX.act(observation, state)
      {:ok, [cx, cy]} = ONNX.action_to_commands(action, MyRobot, state)

      # denorm: value * std + mean = [4.5*2+1, 6.5*2+1] = [10.0, 14.0]
      assert_in_delta cx.value, 10.0, 1.0e-5
      assert_in_delta cy.value, 14.0, 1.0e-5
    end
  end

  describe "action chunking" do
    test "a single-action model infers on every act/2 (queue stays empty)" do
      {:ok, state} = ONNX.init(@policy_opts)
      robot_state = robot_state_with(%{a: 1.0, b: 2.0, c: 3.0})
      {observation, state} = ONNX.observe(robot_state, %{}, state)

      {_a1, state} = ONNX.act(observation, state)
      assert state.action_queue == []
    end
  end

  defp close?(tensor, expected) do
    Nx.all_close(tensor, Nx.tensor(expected), atol: 1.0e-5) |> Nx.to_number() == 1
  end
end
