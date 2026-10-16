<!--
Silicon LogiX / SLX CellProof
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE.
-->

# SLX CellProof API v1

Transport: UTF-8 JSON, one object per line, private stdin/stdout pipes. The SLX
API opens no listening port. Only the RTDE connector opens an outbound connection
to the operator's explicit IPv4 address on port 30004 for controller state.

```json
{"api":"slx.cellproof/v1","id":1,"op":"open","params":{"profile":"demo-ur5e-cnc-v1"}}
```

Success: `{ "api": "slx.cellproof/v1", "id": 1, "ok": true, "result": {} }`.
Errors return `ok:false`, `error.code` and an English `error.message`.
Pass the token returned by `open` in the `session` field of privileged requests.
Existing operation names, error codes, schemas and physical units remain stable in 0.4.0.

| Operation | Purpose |
| --- | --- |
| `open`, `profile.load` | Temporary session and the single supported profile |
| `program.set`, `validate` | SLX source and actual path validation |
| `run`, `tick`, `pause`, `resume`, `step` | Simulated execution and advancement |
| `jog`, `jog.tcp`, `point.teach`, `point.update` | Nominal jog, teach and controlled pose editing |
| `configuration.set`, `recipe.export`, `recipe.import` | Bounded configuration and local recipes |
| `fault.set`, `recover` | Five injected faults and explicit recovery |
| `baseline.save`, `campaign.run`, `report.get` | Baseline, executed tests and JSON/HTML reports |
| `inspector.capture` | Execute bounded isolated current / reference recordings; returns metadata |
| `inspector.info`, `inspector.samples` | Grant-independent recording metadata and bounded sample pages |
| `project.export` | Grant-independent current recipe and baseline snapshot |
| `project.begin`, `project.stage`, `project.commit`, `project.cancel` | Bounded transactional workspace restoration |
| `project.new` | Restore an idle nominal project with no reference |
| `project.file.commit` | Verify and atomically replace a prepared `.cellproof` document |
| `state`, `diagnostics`, `monitor.read` | State accessible without commercial grants |
| `stop`, `pause` | Grant-independent simulation stop and pause |
| `program.reset` | Reset execution while preserving pose and part |
| `simulation.reset` | Explicitly restore the synthetic initial state |
| `monitor.connect`, `monitor.disconnect` | RTDE v2 URSim/UR5e output-only monitoring |
| `grant.verify`, `update.verify` | Ed25519 verification with a compile-time public key |
| `robot.move`, `project.connect` | Rejected: modules unavailable or unqualified in this version |

Limits: 64 KiB frames, JSON nesting 32, 24 KiB programs with 128 instructions,
48 points, simulation step greater than zero and at most 0.25 s. Partial requests
expire after 3 s. A client absent for 5 s stops simulation at the current pose.
Sessions last 30 minutes. Expiry blocks new privileged work; state, monitoring
and stop remain accessible. An existing cycle can still advance, recover and
resume with its current token after expiry.

The contract uses metres/radians/seconds in ROS REP-103. Godot converts only
new state to `(x,z,-y)`; imported GLB geometry is already Y-up. The demonstration
TCP is 0.18 m from `tool0`; UR `base` differs from `base_link`.

## Cycle Inspector

`inspector.capture` accepts `part` (A/B/C), `fault` (none, piece_absent,
door_blocked, machine_permission_missing, sensor_delayed, link_loss) and
`compare_baseline` (default true). It requires a current session, stopped
execution (not paused) and a disconnected monitor. The reference run uses the
same part and no injected fault. It does not replace the reference or alter the
open-cell state. Compilation rejection creates one fault sample at time zero.

The result contains `capture_id`, `current` and optional `baseline` summaries,
`first_difference`, recipe/reference freshness flags and limits. Each summary
includes the source recipe hash, configuration, source program, events, phase
intervals, phase durations, sampled TCP distance, outcome and truncation flag.
Durations are simulated; no controller timing or physical metrology is inferred.

Read frames using `inspector.samples` with the returned `capture_id`, `run`
(current/baseline), zero-based `offset` and `limit` (1–100). The response supplies
`frames`, `total` and `next_offset`. Stale IDs and invalid pages are rejected.
Metadata and samples remain readable without a current commercial/session lease.
Responses are paged; the 64 KiB request limit does not apply to output pages.

Each run is bounded to 6,001 frames at 0.1 s / 600 s. Frames include simulated
`time_s`, joints, TCP/part pose, part availability, door/gripper/clamp state,
connection, source line, instruction index, command, argument and `io`.
The same model signal function drives WAIT and sampled IO. `state` also exposes
these IO values and part availability. No hardware recording is implemented.

`first_difference` compares aligned samples, holding the shorter run's last
state. Thresholds are 0.005 rad for joints and 0.001 m for TCP/door position;
IO, status/error, part availability/location, grip/clamp and command/index are
compared exactly. Source-line-only changes do not create differences. This is
sampled comparison, not continuous equivalence or causal diagnosis.

Local GUI archives use `slx.cellproof.inspector/v1`: `current` and `baseline`
contain `{summary, frames}` plus top-level capture ID, simulated source,
comparison and bookmarks. Imported archives are unsigned/unverified and never
sent to the core. GUI limits are 32 MiB, 256 notes of 200 characters, bounded
poses, a fixed monotonic sample clock and unit quaternions.

SLX supports PTP/LIN with optional SPEED, GRIP OPEN/CLOSE, WAIT with timeout,
CNC DOOR/CLAMP/UNCLAMP/CYCLE and MEASURE. Errors retain original source line
numbers. It is not RAPID, KRL, URScript or a manufacturer controller emulator.

## Complete project transport and storage

`project.export` returns `slx.cellproof.workspace/v1` with a profile, `recipe`
(configuration, points and program) and nullable `baseline`. It remains available
without a lease so existing work can always be exported.

To restore a workspace, serialize that object as UTF-8 and call `project.begin`
with `size_bytes` (1–196,608) and `sha256`. Upload ordered chunks through
`project.stage` using the returned `transaction`, byte `offset` and `chunk_hex`
(at most 4,096 decoded bytes). Finish with `project.commit`. Transactions expire
after 120 seconds; `project.cancel` clears staging. Existing state is unchanged
until both snapshots pass validation. Restoring requires stopped execution and
disconnected monitoring. Joint / TCP consistency, profile, bounds and point names
are checked. Draft SLX syntax is preserved for editing and validated before run.

The GUI's `slx.cellproof.project/v1` document also holds scenario/view settings,
recordings and saved report evidence. Its container stores a JSON document string
and SHA-256; this is corruption detection, not a digital signature.

`project.file.commit` accepts an absolute `target_path` ending in `.cellproof`,
a sibling `temporary_path` with the exact target-name plus `.pending-`, 16 hex
characters and `.cellproof`, the prepared file's `sha256`, the target's
`expected_previous_sha256` (empty when absent), and `keep_backup`. Both the raw
file hash and embedded document checksum are verified within a 40 MiB bound.
Windows uses a per-file mutex and `ReplaceFileW` / `MoveFileExW`; failures retain
the prepared copy. Save remains available during execution and after lease expiry.
This operation does not import data or issue motion commands.

## Update verification

`update.verify` authenticates only a manifest. It does not itself download or
install anything. The GUI update manager separately checks official repository
metadata and downloaded file hashes. Preview policy explicitly permits unsigned
publisher identity; production policy requires an embedded trusted release key,
a signed manifest binding the installer hash/version/publisher and a valid matching
Windows publisher signature. The launcher repeats integrity checks after the
parent application exits. No project, token or controller address is transmitted.
