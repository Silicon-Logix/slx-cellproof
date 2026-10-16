# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends RefCounted
## Local checksummed documents; checksums detect corruption, not authorship.

const Archive = preload("res://inspector_archive.gd")
const SCHEMA := "slx.cellproof.project/v1"
const MAX_BYTES := 40 * 1024 * 1024

static func validate_report(value: Variant) -> bool:
	if value == null:
		return true
	if not value is Dictionary or value.get("schema") != "slx.cellproof.report/v1" or value.get("evidence_source") != "simulated":
		return false
	if not Archive.number(value.get("passed"), 0, 8) or value.get("total") != 8 or not value.get("cases") is Array or value.cases.size() != 8:
		return false
	for item in value.cases:
		if not item is Dictionary or not Archive.text(item.get("part"), 8) or not Archive.text(item.get("fault"), 128) or not item.get("passed") is bool:
			return false
		if not Archive.text(item.get("code", ""), 128) or not Archive.text(item.get("diagnostic", ""), 2048) or not item.get("recovery_verified", false) is bool:
			return false
	var comparison: Variant = value.get("comparison")
	if comparison != null:
		if not comparison is Dictionary or not comparison.get("differences") is Array or comparison.differences.size() > 2:
			return false
		for item in comparison.differences:
			if not item is Dictionary or not Archive.text(item.get("part"), 8) or not Archive.number(item.get("simulated_duration_delta_s"), -5000, 5000) or not item.get("before_passed") is bool or not item.get("after_passed") is bool:
				return false
	return true

static func validate(value: Variant) -> String:
	if not value is Dictionary or value.get("schema") != SCHEMA:
		return "Unsupported CellProof project format"
	if not Archive.text(value.get("project_id"), 64) or value.project_id.length() < 16 or not value.project_id.is_valid_hex_number(false):
		return "Invalid project identifier"
	if not Archive.text(value.get("origin_path", ""), 4096):
		return "Invalid project origin"
	if not value.get("workspace") is Dictionary or value.workspace.get("schema") != "slx.cellproof.workspace/v1" or value.workspace.get("profile") != "demo-ur5e-cnc-v1":
		return "Unsupported project workcell"
	var workspace: Dictionary = value.workspace
	for run in [workspace.get("recipe"), workspace.get("baseline")]:
		if run == null and workspace.get("recipe") != null:
			continue
		if not run is Dictionary or not Archive.text(run.get("program"), 24576) or not run.get("points") is Dictionary or run.points.size() > 48 or not run.get("configuration") is Dictionary:
			return "Invalid recipe or baseline structure"
	if JSON.stringify(workspace).to_utf8_buffer().size() > 196608:
		return "Project recipes exceed 192 KiB"
	if not value.get("settings") is Dictionary:
		return "Invalid project settings"
	var settings: Dictionary = value.settings
	for key in ["page", "pendant", "inspector_part", "inspector_fault"]:
		if not Archive.number(settings.get(key), 0, {"page": 4, "pendant": 2, "inspector_part": 2, "inspector_fault": 5}[key]):
			return "Invalid saved page or scenario"
	if not settings.get("compare_baseline") is bool or not Archive.number(settings.get("replay_time_s"), 0, 600.001) or not Archive.number(settings.get("replay_speed"), 0.25, 5) or not Archive.number(settings.get("simulation_rate"), 1, 5):
		return "Invalid playback settings"
	if not Archive.vector(settings.get("camera"), 3, 1000000) or not Archive.vector(settings.get("inspector_camera"), 3, 1000000):
		return "Invalid saved camera"
	for camera in [settings.camera, settings.inspector_camera]:
		if camera[1] < 0.05 or camera[1] > 1.25 or camera[2] < 1.4 or camera[2] > 9:
			return "Saved camera outside view limits"
	if settings.simulation_rate not in [1.0, 2.0, 5.0] or settings.replay_speed not in [0.25, 0.5, 1.0, 2.0, 5.0]:
		return "Unsupported playback speed"
	for key in ["show_trail", "show_guards", "show_cell_guards", "show_points"]:
		if not settings.get(key, false) is bool:
			return "Invalid presentation setting"
	if settings.has("baseline_camera") and (not Archive.vector(settings.baseline_camera, 3, 1000000) or settings.baseline_camera[1] < 0.05 or settings.baseline_camera[1] > 1.25 or settings.baseline_camera[2] < 1.4 or settings.baseline_camera[2] > 9):
		return "Invalid baseline camera"
	if not validate_report(value.get("report")):
		return "Invalid saved verification report"
	if value.get("recording") != null:
		var error := Archive.validate(value.recording)
		if error != "":
			return "Saved recording: " + error
	return ""

static func read(path: String, allow_backup: bool = true) -> Dictionary:
	var result := _read_one(path)
	if result.has("error") and allow_backup and FileAccess.file_exists(path + ".backup"):
		var backup := _read_one(path + ".backup")
		if not backup.has("error"):
			backup["used_backup"] = true
			return backup
	return result

static func _read_one(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {"error": "Project unreadable or larger than 40 MiB"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"error": "Project container contains invalid JSON"}
	var envelope: Variant = parser.data
	if not envelope is Dictionary or envelope.get("format") != SCHEMA or not envelope.get("document") is String or not envelope.get("sha256") is String:
		return {"error": "Invalid project container"}
	if envelope.document.sha256_text() != envelope.sha256:
		return {"error": "Project checksum mismatch"}
	if parser.parse(envelope.document) != OK:
		return {"error": "Project document contains invalid JSON"}
	var value: Variant = parser.data
	var error := validate(value)
	return {"error": error} if error != "" else {"data": value, "used_backup": false}

static func prepare(path: String, value: Dictionary) -> Dictionary:
	var error := validate(value)
	if error != "":
		return {"error": error}
	var text := JSON.stringify(value)
	var envelope := JSON.stringify({"format": SCHEMA, "document": text, "sha256": text.sha256_text()})
	if envelope.to_utf8_buffer().size() > MAX_BYTES:
		return {"error": "Project exceeds 40 MiB"}
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return {"error": "Cannot create the project folder"}
	var temporary := absolute + ".pending-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".cellproof"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"error": "Cannot write a prepared project copy"}
	file.store_string(envelope)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		DirAccess.remove_absolute(temporary)
		return {"error": "Project copy could not be written completely"}
	var preserve_backup := not FileAccess.file_exists(path + ".backup") or not _read_one(path).has("error")
	return {"target_path": absolute, "temporary_path": temporary, "sha256": FileAccess.get_sha256(temporary),
		"expected_previous_sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "", "keep_backup": preserve_backup}

static func atomic_text(path: String, text: String, backup: bool = true) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		return error
	var temporary := absolute + ".pending-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK and backup and FileAccess.file_exists(absolute):
		error = DirAccess.copy_absolute(absolute, absolute + ".backup")
	if error == OK:
		error = DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error
