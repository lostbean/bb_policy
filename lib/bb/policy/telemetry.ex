# SPDX-FileCopyrightText: 2026 Edgar Gomes de Araujo <talktoedgar@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Policy.Telemetry do
  @moduledoc """
  Telemetry events emitted by `BB.Policy.Runner`.

  Events follow the Beam Bots convention `[:bb, <subsystem>, <operation>, <phase>]`
  and are emitted through `BB.Telemetry` so they share the framework's
  observability tooling.

  ## Events

    * `[:bb, :policy, :episode, :start]` — measurements `%{system_time}`,
      metadata `%{robot, policy_module, goal}`.
    * `[:bb, :policy, :episode, :stop]` — measurements `%{duration, steps}`,
      metadata `%{robot, policy_module, result}`.
    * `[:bb, :policy, :inference, :stop]` — measurements `%{duration}`,
      metadata `%{robot, policy_module, step}`. Emitted per tick; watch p99,
      not the mean — bounded worst-case latency is what matters for control.
    * `[:bb, :policy, :inference, :exception]` — inference raised or failed.

  > #### Status {: .info}
  >
  > Documented contract; wired up alongside the runner loop in the
  > `vertical-slice` phase.
  """
end
