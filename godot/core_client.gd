# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends Node

signal response(operation: String, result: Dictionary)
signal failed(operation: String, code: String, message: String)

var pipe: FileAccess
var errors: FileAccess
var pid := -1
var token := ""
var sequence := 0
var pending: Dictionary = {}
var buffer := PackedByteArray()
var tick_pending := false
var opened := false
var outbound: Array[Dictionary] = []
var in_flight := -1
var last_write_ms := 0

func start() -> void:
	var base := OS.get_executable_path().get_base_dir()
	if not FileAccess.file_exists(base.path_join("bin/slx-cellproof-core.exe" if OS.get_name() == "Windows" else "bin/slx-cellproof-core")):
		base = ProjectSettings.globalize_path("res://..").simplify_path()
	var core := base.path_join("bin/slx-cellproof-core.exe" if OS.get_name() == "Windows" else "bin/slx-cellproof-core")
	if not FileAccess.file_exists(core):
		core = base.path_join("build/public/bin/slx-cellproof-core.exe" if OS.get_name() == "Windows" else "build/public/bin/slx-cellproof-core")
	var process := OS.execute_with_pipe(core, PackedStringArray(), false)
	if process.is_empty():
		failed.emit("startup", "CORE_UNAVAILABLE", "The CellProof core could not be started. Reinstall the complete application package.")
		return
	pipe = process.stdio
	errors = process.stderr
	pid = process.pid
	request("open", {"profile": "demo-ur5e-cnc-v1"})

func request(operation: String, params: Dictionary = {}) -> void:
	if pipe == null:
		return
	sequence += 1
	var bytes := (JSON.stringify({"api": "slx.cellproof/v1", "id": sequence, "op": "open" if operation == "session.renew" else operation, "params": params, "session": token}) + "\n").to_utf8_buffer()
	if bytes.size() > 65536:
		failed.emit(operation, "MESSAGE_LIMIT", "Message too large")
		return
	if outbound.size() >= 32:
		failed.emit(operation, "BUSY", "Command queue full")
		return
	outbound.append({"bytes": bytes, "offset": 0, "op": operation, "id": sequence})
	pending[sequence] = {"op": operation, "sent": 0}
	if operation == "tick":
		tick_pending = true

func _process(_delta: float) -> void:
	if pipe == null:
		return
	# Keep each non-blocking write below the pipe capacity. A saved recipe can
	# be much larger than an ordinary command; transmit it over several frames.
	if not outbound.is_empty() and Time.get_ticks_msec() - last_write_ms >= 20 and (in_flight == -1 or in_flight == int(outbound[0].id)):
		var entry: Dictionary = outbound[0]
		if in_flight == -1:
			# Stamp the current lease immediately before transmission; queued requests
			# must not retain a token replaced by an explicit session renewal.
			var payload: Dictionary = JSON.parse_string(entry.bytes.get_string_from_utf8())
			payload.session = token
			entry.bytes = (JSON.stringify(payload) + "\n").to_utf8_buffer()
			if entry.bytes.size() > 65536:
				outbound.pop_front()
				pending.erase(entry.id)
				failed.emit(entry.op, "MESSAGE_LIMIT", "Message exceeds the transport limit")
				return
			in_flight = entry.id
			pending[in_flight].sent = Time.get_ticks_msec()
		var bytes: PackedByteArray = entry.bytes
		var end := mini(bytes.size(), int(entry.offset) + 2048)
		pipe.store_buffer(bytes.slice(entry.offset, end))
		last_write_ms = Time.get_ticks_msec()
		var write_error := pipe.get_error()
		if write_error == OK:
			entry.offset = end
			if end == bytes.size():
				outbound.pop_front()
		elif write_error != ERR_BUSY:
			failed.emit(entry.op, "PIPE_ERROR", "Incomplete write: session closed to prevent corrupted messages")
			pipe.close()
			pipe = null
			outbound.clear()
			return
	for _batch in range(64):
		var chunk := pipe.get_buffer(8192)
		if chunk.is_empty():
			break
		buffer.append_array(chunk)
		if buffer.size() > 4 * 1024 * 1024:
			failed.emit("transport", "RESPONSE_LIMIT", "Response exceeds size limit")
			shutdown()
			return
		var newline := buffer.find(10)
		while newline >= 0:
			var message = JSON.parse_string(buffer.slice(0, newline).get_string_from_utf8())
			buffer = buffer.slice(newline + 1)
			if message is Dictionary:
				var identifier := int(message.get("id", -1))
				var operation: String = pending.get(identifier, {}).get("op", "unknown")
				pending.erase(identifier)
				if in_flight == identifier:
					in_flight = -1
				if operation == "tick":
					tick_pending = false
				if message.get("ok", false):
					var result: Dictionary = message.get("result", {})
					if operation in ["open", "session.renew"]:
						token = result.session
						opened = true
					response.emit(operation, result)
				else:
					var error: Dictionary = message.get("error", {})
					failed.emit(operation, error.get("code", "ERROR"), error.get("message", "Backend error"))
			newline = buffer.find(10)
	for identifier in pending.keys():
		var entry: Dictionary = pending[identifier]
		var timeout := 120000 if entry.op in ["campaign.run", "inspector.capture"] else 12000
		if entry.sent > 0 and Time.get_ticks_msec() - entry.sent > timeout:
			pending.erase(identifier)
			tick_pending = false
			failed.emit(entry.op, "TIMEOUT", "Backend timeout: state and stop remain accessible")
	if not OS.is_process_running(pid):
		pipe = null
		opened = false
		failed.emit("transport", "CORE_EXITED", "Connection to core interrupted")

func shutdown() -> void:
	if pipe != null:
		# Direct bounded stop on shutdown; closing the pipe is also observed by
		# the backend watchdog and cannot enqueue a new motion command.
		pipe.store_string(JSON.stringify({"api": "slx.cellproof/v1", "op": "stop"}) + "\n")
		pipe.close()
		pipe = null
	if errors != null:
		errors.close()
		errors = null
	outbound.clear()
	# Closing the inherited pipe makes the backend leave its input loop.

func _exit_tree() -> void:
	shutdown()
