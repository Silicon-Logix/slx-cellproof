# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends RefCounted

const SCHEMA := "slx.cellproof.inspector/v1"
const MAX_BYTES := 32 * 1024 * 1024
const IO_KEYS := ["machine_ready", "grip_confirmed", "door_open", "door_closed", "part_present", "clamped", "connected"]
const PHASES := ["Motion", "IO wait", "Machining", "CNC handling", "Gripper", "Measurement"]

static func number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= low and value <= high

static func vector(value: Variant, count: int, bound: float = 100) -> bool:
	if not value is Array or value.size() != count:
		return false
	for component in value:
		if not number(component, -bound, bound):
			return false
	return true

static func text(value: Variant, limit: int = 2048) -> bool:
	return value is String and value.length() <= limit

static func pose(value: Variant) -> bool:
	if not value is Dictionary or not vector(value.get("tcp_xyz_m"), 3) or not vector(value.get("tcp_quaternion_xyzw"), 4, 1.001):
		return false
	var q: Array = value.tcp_quaternion_xyzw
	return absf(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3] - 1) < 0.01

static func validate_run(run: Variant) -> String:
	if not run is Dictionary or not run.get("summary") is Dictionary or not run.get("frames") is Array:
		return "Invalid run structure"
	var meta: Dictionary = run.summary
	var frames: Array = run.frames
	if frames.is_empty() or frames.size() > 6001 or meta.get("frame_count") != frames.size():
		return "Invalid sample count (1 to 6001 required)"
	if meta.get("source") != "simulated" or meta.get("time_source") != "simulated" or not number(meta.get("duration_s"), 0, 600.001) or not number(meta.get("sample_period_s"), 0.1, 0.1):
		return "Only bounded simulated recordings are supported"
	for key in ["outcome", "error_code", "part", "fault", "snapshot_sha256"]:
		if not text(meta.get(key), 128):
			return "Invalid recording metadata"
	if not text(meta.get("program"), 24576) or not number(meta.get("sampled_tcp_path_m"), 0, 100000) or not number(meta.get("completed_instructions"), 0, 128) or not meta.get("truncated") is bool:
		return "Invalid recording statistics"
	if not meta.get("phase_seconds") is Dictionary:
		return "Missing phase statistics"
	for lane in PHASES:
		if not number(meta.phase_seconds.get(lane), 0, 600.001):
			return "Invalid phase duration"
	var config: Variant = meta.get("configuration")
	if not config is Dictionary or not vector(config.get("cnc_offset_m"), 3, 1):
		return "Invalid workcell configuration"
	var proxy: Variant = config.get("obstruction")
	if proxy != null:
		if not proxy is Dictionary or not vector(proxy.get("size_m"), 3, 10) or not vector(proxy.get("center_m"), 3, 10):
			return "Invalid obstruction proxy"
		for component in proxy.size_m:
			if component <= 0:
				return "Invalid obstruction size"
	for i in range(frames.size()):
		var f: Variant = frames[i]
		if not f is Dictionary or not number(f.get("time_s"), 0, 600.001) or absf(f.time_s - i * 0.1) > 0.001:
			return "Invalid sample clock"
		if not vector(f.get("joints_rad"), 6, 50) or not pose(f.get("tcp")) or not pose(f.get("part_pose")):
			return "Invalid sample pose"
		if not number(f.get("line"), 0, 24576) or not number(f.get("program_counter"), 0, 128) or not number(f.get("door_position_m"), 0, 0.851) or not number(f.get("jaw_closure"), 0, 1.001):
			return "Invalid sample state"
		for key in ["command", "argument", "status", "error_code", "part_location", "part_variant"]:
			if not text(f.get(key), 128):
				return "Invalid sample text"
		for key in ["clamped", "gripped", "connected", "part_available"]:
			if not f.get(key) is bool:
				return "Invalid sample flags"
		if not f.get("io") is Dictionary:
			return "Missing sample IO"
		for key in IO_KEYS:
			if not f.io.get(key) is bool:
				return "Invalid sample IO"
	if absf(meta.duration_s - frames.back().time_s) > 0.001:
		return "Recording duration does not match the samples"
	if not meta.get("events") is Array or meta.events.size() > 160 or not meta.get("intervals") is Array or meta.intervals.size() > 128:
		return "Invalid event or phase count"
	for event in meta.events:
		if not event is Dictionary or not number(event.get("time_s"), 0, meta.duration_s + 0.001) or not text(event.get("code"), 128) or not text(event.get("message")) or not number(event.get("line"), 0, 24576):
			return "Invalid event"
	for interval in meta.intervals:
		if not interval is Dictionary or interval.get("phase") not in PHASES or not number(interval.get("start_s"), 0, meta.duration_s + 0.001) or not number(interval.get("end_s"), interval.start_s, meta.duration_s + 0.001):
			return "Invalid phase interval"
	return ""

static func validate(value: Variant) -> String:
	if not value is Dictionary or value.get("schema") != SCHEMA or value.get("source") != "simulated" or not text(value.get("capture_id"), 128):
		return "Unsupported Cycle Inspector recording"
	var error := validate_run(value.get("current"))
	if error != "":
		return error
	if value.get("baseline") != null:
		error = validate_run(value.baseline)
		if error != "":
			return "Baseline: " + error
	var difference: Variant = value.get("first_difference")
	if difference != null:
		if value.get("baseline") == null or not difference is Dictionary or not number(difference.get("time_s"), 0, 600.001) or not difference.get("reasons") is Array or difference.reasons.size() > 32:
			return "Invalid comparison"
		for reason in difference.reasons:
			if not text(reason, 128):
				return "Invalid difference description"
	var marks: Variant = value.get("bookmarks", [])
	if not marks is Array or marks.size() > 256:
		return "Too many bookmarks"
	for mark in marks:
		if not mark is Dictionary or not number(mark.get("time_s"), 0, value.current.summary.duration_s) or not text(mark.get("note"), 200):
			return "Invalid bookmark"
	return ""

static func write_csv(path: String, recording: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var header: Array = ["run", "source", "time_s", "line", "command", "argument", "status", "error_code", "j1_rad", "j2_rad", "j3_rad", "j4_rad", "j5_rad", "j6_rad", "tcp_x_m", "tcp_y_m", "tcp_z_m", "door_m", "jaw_closure", "gripped", "clamped"]
	for key in IO_KEYS:
		header.append("io_" + key)
	file.store_csv_line(PackedStringArray(header))
	for name in ["current", "baseline"]:
		if recording.get(name) == null:
			continue
		for frame in recording[name].frames:
			var row: Array = [name, "simulated", frame.time_s, frame.line, frame.command, frame.argument, frame.status, frame.error_code]
			row.append_array(frame.joints_rad)
			row.append_array(frame.tcp.tcp_xyz_m)
			row.append_array([frame.door_position_m, frame.jaw_closure, frame.gripped, frame.clamped])
			for key in IO_KEYS:
				row.append(frame.io[key])
			var fields := PackedStringArray()
			for item in row:
				var cell := str(item)
				# Quoting CSV fields does not prevent spreadsheet formula evaluation.
				if item is String and cell.strip_edges().left(1) in ["=", "+", "-", "@"]:
					cell = "'" + cell
				fields.append(cell)
			file.store_csv_line(fields)
	file.flush()
	return file.get_error()
