<!--
Silicon LogiX / SLX CellProof
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE.
-->

# CellProof user guide

## Complete projects and recovery

Use **Project / New project**, **Open project**, **Save project** and **Save
project as** for complete `.cellproof` documents. They include the current
recipe, reference baseline, selected inspector scenario, recorded cycles and
notes, saved verification evidence, camera / playback settings and view toggles.
Recipe-only JSON import and export remain under **Programming**.

Opening a project validates and restores both recipe snapshots together, then
starts an **idle** local simulation. It never reconnects a controller, resumes
a previous cycle or sends physical motion. Stop a running / paused cycle and
disconnect monitoring before replacing a project. Incomplete or invalid imports
preserve the currently open project. Unfinished SLX drafts can be saved; program
execution still requires normal syntax and geometry validation.

Unsaved changes appear in the title. Replacing a dirty project or closing the
window offers **Save / Discard / Cancel**. A file modified by another application
is protected: use **Save project as** to preserve both versions. The previous
successful save is kept in a `.backup` companion. **Restore previous save**
loads it; a corrupt main document can fall back to a valid backup.

Autosave defaults to 30 seconds and writes local recovery copies without marking
the project saved. Change its interval (15–600 seconds) under **Project settings**.
At the next normal start, available copies are offered under **Recover autosave**.
Recovery leaves the simulation idle and the document unsaved; choose a path
explicitly. **Recent projects** retains the last ten explicit project paths.
**Renew demo session** replaces an expired temporary session while preserving
the project and unsaved text; it does not add capabilities or resume execution.

Project replacement uses a bounded native transaction. Saving writes and flushes
a prepared copy, verifies its checksum and uses Windows atomic replacement with
a per-file lock. If replacement fails, the prepared copy is retained. Project
and archive checksums detect corruption, not authorship; reopened recordings and
reports are labeled local / unverified. Files may contain programs and notes.

## Start a verification

Select **Part A** or **Part B** and choose **Validate program**. The core checks
the SLX instructions and sampled motion geometry. Choose **Run** to execute
the nominal simulation. Use **Pause**, **Resume** and **STOP** as needed.
The STOP button controls the local simulation.

Part C is a deliberate incompatibility: its 60 mm diameter leaves no gripping
clearance with the demonstration gripper. Rejection is an expected test outcome.

## Program and teach

Edit the SLX program in **Programming / SLX editor**. The pendant provides
joint jog, TCP jog and **Step - one instruction**. Distances are displayed in
millimetres; the API uses metres, radians and seconds.

In **Points**, choose a taught point, edit its position and select **Save edited
pose**. Its orientation is preserved. Use **Teach current pose** with a unique
point name to add a pose. Geometry and IK checks are performed by the core.
**Add test fixture** inserts an obstruction at the CNC entrance to exercise
geometry rejection after a tooling change.

Program reset preserves pose and part state. **Reset simulation** explicitly
restores the synthetic initial state. Stop the running cycle before editing
the configuration or loading another recipe.

## Compare a change

Save the current baseline, edit the recipe or taught points, then choose
**Verify change**. The campaign executes nominal parts A/B, incompatible C and
five injected faults: absent part, blocked door, missing machine permission,
delayed sensor and connection loss. Fault cases also verify completed recovery.

The results table shows pass/fail, diagnostics and recovery status. The previous
nominal baseline is rerun for comparison. The first campaign establishes a
baseline if none has been saved. Every completed campaign then replaces the
reference with its current recipe; save the desired reference again when needed.

## Inspect a cycle

Open **Cycle Inspector**, choose a part and nominal or fault scenario, then
choose **Record cycle**. Stop any running or paused cycle and disconnect the
controller monitor first. Recording executes a fresh copy of the recipe;
it preserves the open cell's pose, program counter and reference.

Enable **Compare baseline** to execute the saved reference for the same part
without an injected fault. Save the reference under **Verify change** before
editing the recipe. Both views follow a shared simulated clock. The shorter
run holds its final sample after it ends.

Use **Play**, the speed selector, the scrubber or a click on the timeline.
**Event**, **Fault** and **First difference** jump to the corresponding times.
Colored lanes show executed phases; lower lanes show sampled door, grip and
permission signals. Solid upper bars are current; pale lower bars are the
reference. The event table supports text filtering and click-to-seek.
**TCP trail**, **Guards**, orbit, zoom and **Reset view** affect presentation.

The summary shows simulated phase durations and approximate sampled TCP path
length. The first difference compares joints (0.005 rad), TCP (1 mm), door
position (1 mm), IO and discrete program / part states. It identifies a sampled
difference, not a root cause or a collision-free interval between samples.

Recordings use 100 ms steps, up to 600 s / 6,001 samples per run. They stop at
the first fault or rejection; long cycles are explicitly marked **TRUNCATED**.
Changing the core recipe or reference marks its recording stale. Unsaved editor
changes enter the core when **Record cycle** synchronizes the program.

Add a **Bookmark** with a note to the current position. Select its table row
and choose **Remove** to delete it. **Export** saves a complete JSON recording
with notes or a CSV table containing both runs, joints, TCP, CNC and IO.
**Open recording** validates a local JSON file (32 MiB maximum) and labels it
**UNVERIFIED**. Archives are unsigned, may contain recipe text and user notes,
and are opened only for viewing; they never upload or execute a program.

## Fault recovery

Choose a simulated fault in **Pendant** and execute the program. After the fault
is detected, **Clear simulated faults** removes the cause while preserving pose
and part. Choose **Resume** explicitly. Starting a new cycle requires a valid
initial workcell state; use the explicit simulation reset when appropriate.

## Save recipes and reports

**Open** and **Save** in Programming handle local recipes: program, taught points and
the permitted workcell configuration. **Export report** saves readable HTML or
structured JSON evidence. Files are written only to the path you choose.
An enquiry under **SLX services** copies your entered brief without sending
recipes or installation files automatically.
Its **Request this integration** action pre-fills the selected service topic.
See [advanced integrations](ADVANCED_FEATURES.md) for scope and official references.

Campaign durations are simulated; host processing time is separate. Dimensional
results are synthetic demonstration data. See [validation coverage](VALIDATION.md).

## Connect a controller

Open **Connections**, choose URSim or the UR5e monitor, enter an explicit IPv4
address and choose **Connect read only**. The 3D joints follow received RTDE
telemetry. Stale data and connection loss are flagged. Monitoring sends no
physical motion commands. Workcell placement and TCP remain nominal until
calibrated for a specific installation. See [URSim setup](URSIM.md).

## Help and product information

The **Help** menu opens this guide, the SLX reference, the license and complete
third-party notices. **About** shows product/core/runtime versions, author and
copyright. **Copy system info** copies only product version, runtime version,
platform and core connection status; it excludes paths, controller addresses,
session tokens and recipe contents.

| Shortcut | Action |
| --- | --- |
| F1 | User guide |
| F12 | About CellProof |
| Ctrl+N | New project, with unsaved-change protection |
| Ctrl+O | Open a complete project |
| Ctrl+S | Save the complete project |
| Ctrl+Shift+S | Save the project to another path |
| Escape | Close the active dialog |

## Installation and updates

The Windows installer uses your user profile, creates shortcuts and optionally
associates `.cellproof` files. Uninstall preserves projects and recovery data.
Portable packages remain available. **Help / Check for updates** contacts only
the official repository after an explicit request. Downloaded installers are
bounded and checked against the release SHA-256 before launch; dirty projects
are protected by the normal save prompt.

The preview is unsigned and does not authenticate a Windows publisher. Production
policy requires a trusted signed manifest and a matching valid Windows publisher
signature. See [installation and updates](INSTALLATION_AND_UPDATES.md) for manual
verification, recovery and deliberate rollback.

## Troubleshooting

- If the core cannot start, extract the complete package again and keep its
  companion files together. The source bundle needs the included `bin/` directory.
- If a path is rejected, check the original SLX line, taught pose, fixture and
  door state. Rejection does not silently replace the requested LIN path.
- If a controller stays stale, check its address, RTDE availability and URSim
  initialization. Physical controller connectivity requires installation testing.
- If Windows displays an old shortcut icon, recreate the shortcut to the current
  executable; the file and taskbar icons are included in the package.
