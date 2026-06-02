# SPDX-FileCopyrightText: 2026 Edgar Gomes de Araujo <talktoedgar@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

Application.ensure_all_started(:mimic)

# Boundary modules from bb core that BB.Policy.Runner / ActuatorCommand call.
# Tests stub these with Mimic so the runner can be exercised without a live
# robot or hardware.
Mimic.copy(BB.Safety)
Mimic.copy(BB.Robot.Runtime)
Mimic.copy(BB.Actuator)

ExUnit.start()
