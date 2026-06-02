# SPDX-FileCopyrightText: 2026 Edgar Gomes de Araujo <talktoedgar@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

defmodule BbPolicyFirmware.MixProject do
  use Mix.Project

  @app :bb_policy_firmware
  @all_targets [:rpi0_2]

  def project do
    [
      app: @app,
      version: "0.1.0",
      elixir: "~> 1.19",
      archives: [nerves_bootstrap: "~> 1.13"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}],
      preferred_cli_target: [run: :host, test: :host]
    ]
  end

  # Run on host with `iex -S mix`, on target with `MIX_TARGET=rpi0_2 mix firmware`.
  def application do
    [
      mod: {BbPolicyFirmware.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      # Dependencies for all targets
      {:nerves, "~> 1.10", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.4.0"},

      # The package under test (local) + core.
      {:bb_policy, path: ".."},
      {:bb, "~> 0.20"},
      # ortex is gated by ORTEX=1 in bb_policy's mix.exs; force it on for firmware
      # by exporting ORTEX=1 before `mix deps.get`/`mix firmware`. See the runbook.

      # Dependencies for host (no target)
      {:nerves_runtime, "~> 0.13.0", targets: @all_targets},
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},

      # Pi Zero 2 W system + toolchain
      {:nerves_system_rpi0_2, "~> 2.0", runtime: false, targets: :rpi0_2}
    ]
  end

  defp release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod
    ]
  end
end
