<!--
Silicon LogiX / SLX CellProof
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE.
-->

# URSim verification

The demo contains a read-only RTDE v2 connector. It has been exercised from
the Windows core against official URSim e-Series 5.23.0 in Docker/WSL with
35 valid controller samples and increasing timestamps. It sends no URScript,
RTDE input recipes, robot programs or physical motion commands.

The verified image is pinned to:

```text
universalrobots/ursim_e-series@sha256:f1211a7feb4252135b1439f603f4e17ff826b4b71574f3963c868efe0498b4a9
```

In a prepared Docker environment:

```bash
docker run --name slx-cellproof-ursim -e ROBOT_MODEL=UR5 \
  -p 127.0.0.1:30004:30004 -p 127.0.0.1:6080:6080 \
  universalrobots/ursim_e-series@sha256:f1211a7feb4252135b1439f603f4e17ff826b4b71574f3963c868efe0498b4a9
```

Open `http://127.0.0.1:6080/vnc.html` and complete the virtual simulator's initial
setup and safety configuration confirmation. Until confirmed, the controller
may send informational messages without RTDE samples; CellProof waits and
indicates stale data. This setup concerns the virtual simulator only.

In CellProof open **Connections**, select URSim, enter its explicit IPv4 address
and choose **Connect read only**. No controller address is preconfigured.
Received joints drive the 3D view. Controller TCP coordinates use the UR `base`
frame; the visual workcell placement remains nominal.

After connection, verify that the controller timestamp increases and the view follows received joint data. Disconnect from the Connections page when finished.

URSim is a separately prepared manufacturer component and is not included in
SLX public archives. Physical connectivity and any future motion integration
require their own calibration, authorization and commissioning.
