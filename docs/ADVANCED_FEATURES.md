<!--
Silicon LogiX / SLX CellProof
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE.
-->

# Advanced integrations on request

Reviewed against official documentation on 2026-10-16. These are proposed
engineering scopes. They require an agreed installation, implementation and
acceptance tests; they are not activated or included by a demo license grant.
The bundled **SLX services** catalogue presents the same offers and lets the
operator prepare a local enquiry without transmitting files or programs.

| Integration | Inputs required | Proposed result |
| --- | --- | --- |
| Calibrated digital model | Cell CAD, factory robot calibration, measured base/TCP, tooling and tolerances | Versioned model, measured frame residuals and installation acceptance report |
| Controller traces and IO correlation | RTDE recipes, PLC mapping, clock strategy, controller versions and representative traces | Read-only recording adapter with timestamps, gaps and acquisition-quality indicators |
| OPC UA machine / robot monitoring | Endpoints, certificates, supported namespaces, node inventory and vendor options | Mapped adapter and interoperability tests for the agreed companion-model subset |
| Motion planning / cycle optimization | Calibrated collision geometry, velocity/acceleration/jerk limits, payload and process constraints | Benchmarked candidate trajectories, collision rechecks and timing comparison |
| Virtual commissioning | URDF/SDF, actuator behavior, controller/PLC interfaces, interlocks and recovery scenarios | Repeatable simulation environment and fault/recovery acceptance campaign |

## Technical basis and limits

UR's factory calibration package provides robot-specific kinematics for a
URDF model. A useful installation model also needs measured workcell and tool
frames; nominal meshes alone cannot establish installation accuracy.
See the [official UR calibration package](https://github.com/UniversalRobots/Universal_Robots_ROS2_Driver/blob/main/ur_calibration/README.md).

RTDE exposes controller timestamps, joint/TCP state and digital IO. The guide
describes skipped output packets under controller load, so a recorder needs
timestamp continuity checks and visible acquisition gaps. The existing demo
monitor subscribes to a smaller output-only recipe; hardware trace recording
and PLC clock correlation would be new integrations.
See the [official RTDE guide](https://docs.universal-robots.com/tutorials/communication-protocol-tutorials/rtde-guide.html).

OPC UA Machine Tools models monitoring and job information; Robotics provides
an equipment information model. Actual nodes, optional features and vendor
support must be discovered and mapped. Monitoring does not imply PLC interlock
or physical-motion control. See the OPC Foundation's
[MachineToolType specification](https://reference.opcfoundation.org/specs/OPC-40501-1/8.1)
and [Robotics specification](https://reference.opcfoundation.org/specs/OPC-40010-1).

MoveIt 2 documents trajectory time parameterization with velocity/acceleration
limits and subsequent Ruckig jerk smoothing. Its path-fitting parameterization
can alter waypoints, requiring collision rechecks. This makes constrained
trajectory evaluation a plausible integration; it does not establish a cycle
time improvement for an unmeasured installation. See
[MoveIt time parameterization](https://moveit.picknik.ai/main/doc/examples/time_parameterization/time_parameterization_tutorial.html).

Gazebo's `gz_ros2_control` connects simulated mechanisms to a ROS 2 controller
manager and supports custom simulated behavior. PLC emulation, process physics
and fault semantics still require installation-specific development. See the
[official Gazebo / ros2_control documentation](https://control.ros.org/jazzy/doc/gz_ros2_control/doc/index.html).

## Included in 0.4.0

Cycle Inspector records **simulated** cycles now: synchronized current/reference
replay, sampled command/IO timeline, first sampled difference, local notes and
JSON/CSV export. URSim/UR5e monitoring remains read only. The public package
contains no physical-motion, OPC UA, MoveIt or Gazebo execution module.
See the [user guide](USER_GUIDE.md) and [validation limits](VALIDATION.md).
