# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends VBoxContainer

const View = preload("res://workcell_view.gd")
const Timeline = preload("res://cycle_timeline.gd")
const Archive = preload("res://inspector_archive.gd")
const Palette = preload("res://slx_theme.gd")
const FAULTS := ["none", "piece_absent", "door_blocked", "machine_permission_missing", "sensor_delayed", "link_loss"]
var app: Node
var recording: Dictionary = {}
var info: Dictionary = {}
var previous_recording: Dictionary = {}
var previous_info: Dictionary = {}
var loading := false
var busy := false
var imported := false
var playing := false
var play_time := 0.0
var speed := 1.0
var current_view: SubViewportContainer
var baseline_view: SubViewportContainer
var baseline_panel: VBoxContainer
var timeline: Control
var slider: HSlider
var badge: Label
var metrics: Label
var comparison: Label
var current_caption: Label
var baseline_caption: Label
var clock: Label
var details: Label
var play_button: Button
var capture_button: Button
var part: OptionButton
var fault: OptionButton
var speed_select: OptionButton
var guards_toggle: CheckButton
var compare: CheckButton
var trail: CheckButton
var events: Tree
var search: LineEdit
var note: LineEdit
var open_dialog: FileDialog
var save_dialog: FileDialog
var save_csv := false

func attach(owner_app: Node) -> void:
	app = owner_app
	name = "Cycle Inspector"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	var heading := HBoxContainer.new()
	heading.add_child(app._label("Cycle Inspector", 27))
	badge = app._label("Record a cycle to begin", 12, Palette.MUTED)
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(badge)
	add_child(heading)
	app._note(self, "Recorded simulation · 100 ms samples · isolated from the open cell · up to 600 s per run. Baseline runs use the same part without injected faults.")
	var actions := HBoxContainer.new()
	part = OptionButton.new()
	for title in ["Part A", "Part B", "Part C / incompatible"]:
		part.add_item(title)
	actions.add_child(part)
	fault = OptionButton.new()
	for title in ["Nominal", "Part absent", "Door blocked", "Permission missing", "Sensor delayed", "Connection lost"]:
		fault.add_item(title)
	actions.add_child(fault)
	compare = CheckButton.new()
	compare.text = "Compare baseline"
	compare.button_pressed = true
	actions.add_child(compare)
	capture_button = app._button("Record cycle", begin_capture, true)
	actions.add_child(capture_button)
	actions.add_child(app._button("Open recording", func(): open_dialog.popup_centered_ratio(0.72)))
	var export_menu := MenuButton.new()
	export_menu.text = "Export…"
	export_menu.get_popup().add_item("Recording + bookmarks (.json)", 0)
	export_menu.get_popup().add_item("Samples for analysis (.csv)", 1)
	export_menu.get_popup().id_pressed.connect(func(id: int):
		if recording.is_empty() or busy:
			return
		save_csv = id == 1
		save_dialog.filters = PackedStringArray(["*.csv ; Sample table"] if save_csv else ["*.json ; Cycle Inspector recording"])
		save_dialog.current_file = "cellproof-cycle.csv" if save_csv else "cellproof-cycle.json"
		save_dialog.popup_centered_ratio(0.72))
	actions.add_child(export_menu)
	add_child(actions)
	metrics = app._label("Simulated duration, phase breakdown and sampled TCP distance appear after recording.", 13, Palette.MUTED)
	metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(metrics)
	comparison = app._label("Save a baseline from Verify change to compare two recipes.", 13, Palette.MUTED)
	comparison.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(comparison)
	var views := HBoxContainer.new()
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var current_panel: VBoxContainer = app._vbox(2)
	current_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	current_caption = app._label("CURRENT · RECORDED SIMULATION", 12, Palette.ACCENT)
	current_panel.add_child(current_caption)
	current_view = View.new()
	current_view.custom_minimum_size = Vector2(300, 180)
	current_panel.add_child(current_view)
	views.add_child(current_panel)
	baseline_panel = app._vbox(2)
	baseline_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	baseline_caption = app._label("BASELINE · RECORDED SIMULATION", 12, Palette.SUCCESS)
	baseline_panel.add_child(baseline_caption)
	baseline_view = View.new()
	baseline_view.custom_minimum_size = Vector2(300, 180)
	baseline_panel.add_child(baseline_view)
	views.add_child(baseline_panel)
	baseline_panel.visible = false
	add_child(views)
	var controls := HBoxContainer.new()
	play_button = app._button("Play", toggle_play)
	controls.add_child(play_button)
	controls.add_child(app._button("‹ Event", func(): step_event(-1)))
	controls.add_child(app._button("Event ›", func(): step_event(1)))
	controls.add_child(app._button("First difference", jump_difference))
	controls.add_child(app._button("Fault", jump_fault))
	var rates := OptionButton.new()
	speed_select = rates
	for rate in ["0.25×", "0.5×", "1×", "2×", "5×"]:
		rates.add_item(rate)
	rates.select(2)
	rates.item_selected.connect(func(index: int): speed = [0.25, 0.5, 1.0, 2.0, 5.0][index])
	controls.add_child(rates)
	trail = CheckButton.new()
	trail.text = "TCP trail"
	trail.button_pressed = true
	trail.toggled.connect(func(value: bool): current_view.trace.visible = value; baseline_view.trace.visible = value)
	controls.add_child(trail)
	var guards := CheckButton.new()
	guards_toggle = guards
	guards.text = "Guards"
	guards.toggled.connect(func(value: bool): current_view.set_guards(value); baseline_view.set_guards(value))
	controls.add_child(guards)
	controls.add_child(app._button("Reset view", func():
		for view in [current_view, baseline_view]:
			view.angle = -2.3; view.elevation = 0.46; view.distance = 4.8; view._update_camera()))
	clock = app._label("0.0 / 0.0 s", 13)
	clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.add_child(clock)
	add_child(controls)
	slider = HSlider.new()
	slider.step = 0.1
	slider.value_changed.connect(func(value: float): playing = false; seek(value))
	add_child(slider)
	timeline = Timeline.new()
	timeline.seek_requested.connect(func(value: float): playing = false; seek(value))
	add_child(timeline)
	var lower := HBoxContainer.new()
	var event_panel: VBoxContainer = app._vbox(4)
	event_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search = LineEdit.new()
	search.placeholder_text = "Filter events, codes, source lines or bookmarks"
	search.text_changed.connect(func(_value: String): render_events())
	event_panel.add_child(search)
	events = Tree.new()
	events.custom_minimum_size.y = 95
	events.columns = 4
	events.hide_root = true
	events.column_titles_visible = true
	for i in range(4):
		events.set_column_title(i, ["Time", "Run", "Event / line", "Details"][i])
		events.set_column_expand(i, i == 3)
		events.set_column_custom_minimum_width(i, [65, 75, 180, 200][i])
	events.item_selected.connect(func():
		var item := events.get_selected()
		if item:
			playing = false
			seek(float(item.get_metadata(0).time_s)))
	event_panel.add_child(events)
	lower.add_child(event_panel)
	var side: VBoxContainer = app._vbox(4)
	side.custom_minimum_size.x = 275
	details = app._label("Scrub to inspect robot, CNC and IO state.", 12, Palette.MUTED)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(details)
	note = LineEdit.new()
	note.max_length = 200
	note.placeholder_text = "Bookmark note at this time"
	note.tooltip_text = "Optional note for the bookmark at the selected simulation time"
	note.custom_minimum_size.x = 90
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.text_submitted.connect(func(_value: String): add_bookmark())
	var marks := HBoxContainer.new()
	marks.add_child(note)
	marks.add_child(app._button("Bookmark", add_bookmark))
	marks.add_child(app._button("Remove", remove_bookmark))
	side.add_child(marks)
	lower.add_child(side)
	add_child(lower)
	open_dialog = FileDialog.new()
	open_dialog.title = "Open a local Cycle Inspector recording"
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_dialog.filters = PackedStringArray(["*.json ; Cycle Inspector recording"])
	open_dialog.file_selected.connect(open_recording)
	add_child(open_dialog)
	save_dialog = FileDialog.new()
	save_dialog.title = "Export Cycle Inspector data"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.file_selected.connect(save_recording)
	add_child(save_dialog)

func capture_parameters() -> Dictionary:
	return {"part": ["A", "B", "C"][part.selected], "fault": FAULTS[fault.selected], "compare_baseline": compare.button_pressed}

func begin_capture() -> void:
	if busy or not app.backend_ready or app.campaign_busy or app.pending_action != "":
		return
	app._sync_then("inspector.capture")
	if app.pending_action == "inspector.capture":
		previous_recording = recording
		previous_info = info
		busy = true
		playing = false
		capture_button.disabled = true
		badge.text = "Recording isolated simulation…"

func handle_response(operation: String, result: Dictionary) -> void:
	if operation == "inspector.info":
		if not imported and not info.is_empty() and result.get("capture_id") == info.get("capture_id"):
			info = result
			refresh_badge()
		return
	if operation == "inspector.capture":
		loading = true
		info = result
		recording = {"schema": Archive.SCHEMA, "capture_id": result.capture_id, "source": "simulated", "first_difference": result.first_difference,
			"current": {"summary": result.current, "frames": []}, "baseline": null, "bookmarks": []}
		if result.baseline != null:
			recording.baseline = {"summary": result.baseline, "frames": []}
		request_page("current", 0)
	elif operation == "inspector.samples":
		if result.capture_id != recording.get("capture_id"):
			fail_load("Recording changed while downloading; record again")
			return
		var run: String = result.run
		var frames: Array = recording[run].frames
		if int(result.offset) != frames.size():
			fail_load("Unexpected recording page; record again")
			return
		frames.append_array(result.frames)
		badge.text = "Loading %s samples · %d / %d" % [run, frames.size(), result.total]
		if frames.size() < int(result.total):
			request_page(run, frames.size())
		elif run == "current" and recording.baseline != null:
			request_page("baseline", 0)
		else:
			var error := Archive.validate(recording)
			if error != "":
				fail_load(error)
				return
			imported = false
			finish_load()

func request_page(run: String, offset: int) -> void:
	app.core.request("inspector.samples", {"capture_id": recording.capture_id, "run": run, "offset": offset, "limit": 100})

func fail_load(message: String) -> void:
	if loading:
		recording = previous_recording
		info = previous_info
		loading = false
	busy = false
	playing = false
	capture_button.disabled = false
	badge.text = message

func finish_load() -> void:
	loading = false
	previous_recording = {}
	previous_info = {}
	busy = false
	playing = false
	capture_button.disabled = false
	var meta: Dictionary = recording.current.summary
	metrics.text = "SIMULATED  %.1f s · motion %.1f s · IO wait %.1f s · machining %.1f s · handling %.1f s · TCP path ≈ %.2f m" % [meta.duration_s, meta.phase_seconds.Motion, meta.phase_seconds["IO wait"], meta.phase_seconds.Machining, meta.phase_seconds["CNC handling"] + meta.phase_seconds.Gripper, meta.sampled_tcp_path_m]
	baseline_panel.visible = recording.baseline != null
	comparison.text = "Current only · save a reference in Verify change, then record with Compare baseline."
	if recording.baseline != null:
		var difference: Variant = recording.first_difference
		comparison.text = "No difference above the sampled comparison thresholds."
		if difference != null:
			comparison.text = "First sampled difference at %.1f s · %s" % [difference.time_s, ", ".join(difference.reasons)]
		comparison.text += " · Δ duration %+.1f s" % (meta.duration_s - recording.baseline.summary.duration_s)
	if meta.truncated or (recording.baseline != null and recording.baseline.summary.truncated):
		comparison.text += " · TRUNCATED at the 600 s recording limit"
	timeline.intervals = meta.intervals
	timeline.baseline_intervals = recording.baseline.summary.intervals if recording.baseline != null else []
	timeline.events = meta.events
	timeline.bookmarks = recording.get("bookmarks", [])
	timeline.duration = duration()
	timeline.set_samples(recording.current.frames, recording.baseline.frames if recording.baseline != null else [])
	slider.max_value = duration()
	current_view.set_trace_path(recording.current.frames, Palette.ACCENT)
	if recording.baseline != null:
		baseline_view.set_trace_path(recording.baseline.frames, Palette.SUCCESS)
	current_view.trace.visible = trail.button_pressed
	baseline_view.trace.visible = trail.button_pressed
	refresh_badge()
	render_events()
	seek(0)
	if is_instance_valid(app.projects):
		app.projects.mark_dirty()

func refresh_badge() -> void:
	if imported:
		badge.text = "LOCAL RECORDING · UNVERIFIED · SIMULATED"
	else:
		var stale: bool = not info.get("current_matches_recipe", false) or app.editor.text != recording.current.summary.program or (recording.get("baseline") != null and not info.get("baseline_matches_reference", false))
		badge.text = "RECORDED SIMULATION" + (" · RECIPE / REFERENCE CHANGED" if stale else " · CURRENT RECIPE")

func duration() -> float:
	if recording.is_empty():
		return 0
	var end: float = recording.current.summary.duration_s
	if recording.baseline != null:
		end = maxf(end, recording.baseline.summary.duration_s)
	return end

func frame_at(run: String, time_s: float) -> Dictionary:
	var frames: Array = recording[run].frames
	return frames[clampi(int(floor((time_s + 0.00001) / 0.1)), 0, frames.size() - 1)]

func seek(time_s: float) -> void:
	if recording.is_empty() or busy:
		return
	play_time = clampf(time_s, 0, duration())
	slider.set_value_no_signal(play_time)
	timeline.playhead = play_time
	timeline.queue_redraw()
	var frame := frame_at("current", play_time).duplicate()
	frame.configuration = recording.current.summary.configuration
	current_view.apply_state(frame)
	current_caption.text = "CURRENT · %s · line %d · %s %s" % [frame.status.to_upper(), frame.line, frame.command, frame.argument]
	if recording.baseline != null:
		var before := frame_at("baseline", play_time).duplicate()
		before.configuration = recording.baseline.summary.configuration
		baseline_view.apply_state(before)
		baseline_caption.text = "BASELINE · %s · line %d · %s %s" % [before.status.to_upper(), before.line, before.command, before.argument]
	clock.text = "%.1f / %.1f s" % [play_time, duration()]
	var p: Array = frame.tcp.tcp_xyz_m
	details.text = "RECORDED IO · t = %.1f s\nTCP  %.1f / %.1f / %.1f mm\nDoor %s · grip %s · clamp %s\nPermission %s · link %s%s" % [frame.time_s, p[0]*1000, p[1]*1000, p[2]*1000, "open" if frame.io.door_open else "closed / moving", "ON" if frame.gripped else "OFF", "ON" if frame.clamped else "OFF", "ON" if frame.io.machine_ready else "OFF", "ON" if frame.connected else "OFF", ("\n" + frame.error_code) if frame.error_code != "" else ""]
	play_button.text = "Pause" if playing else "Play"
	if app.pages.current_tab == 4:
		app._inspector_context()

func toggle_play() -> void:
	if recording.is_empty() or busy:
		return
	playing = not playing
	if playing and play_time >= duration():
		seek(0)
	seek(play_time)

func _process(delta: float) -> void:
	if playing and is_visible_in_tree() and not busy:
		seek(play_time + delta * speed)
		if play_time >= duration():
			playing = false
			play_button.text = "Play"

func all_events() -> Array:
	var result: Array = []
	if recording.is_empty():
		return result
	for run in ["current", "baseline"]:
		if recording.get(run) == null:
			continue
		for event in recording[run].summary.events:
			result.append({"time_s": event.time_s, "run": run, "code": event.code, "line": event.line, "message": event.message})
	for i in range(recording.get("bookmarks", []).size()):
		var mark: Dictionary = recording.bookmarks[i]
		result.append({"time_s": mark.time_s, "run": "current", "code": "BOOKMARK", "line": 0, "message": mark.note, "bookmark_index": i})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return a.time_s < b.time_s)
	return result

func render_events() -> void:
	events.clear()
	var root := events.create_item()
	for event in all_events():
		if search.text != "" and not (event.code + " " + event.message + " " + str(event.line) + " " + event.run).to_lower().contains(search.text.to_lower()):
			continue
		var item := events.create_item(root)
		item.set_text(0, "%.1f s" % event.time_s)
		item.set_text(1, event.run)
		item.set_text(2, "%s / L%d" % [event.code, event.line])
		item.set_text(3, event.message)
		item.set_metadata(0, event)
		if event.code not in ["STARTED", "STEP_COMPLETED", "COMPLETED", "BOOKMARK"]:
			item.set_custom_color(2, Palette.FAILURE)
	timeline.queue_redraw()

func step_event(direction: int) -> void:
	var entries := all_events()
	if direction < 0:
		entries.reverse()
	for entry in entries:
		if (direction > 0 and entry.time_s > play_time + 0.001) or (direction < 0 and entry.time_s < play_time - 0.001):
			playing = false
			seek(entry.time_s)
			return

func jump_difference() -> void:
	if not recording.is_empty() and recording.get("first_difference") != null:
		playing = false
		seek(recording.first_difference.time_s)

func jump_fault() -> void:
	for event in all_events():
		if event.run == "current" and event.code not in ["STARTED", "STEP_COMPLETED", "COMPLETED", "BOOKMARK"]:
			playing = false
			seek(event.time_s)
			return

func add_bookmark() -> void:
	if recording.is_empty() or busy or recording.bookmarks.size() >= 256:
		return
	recording.bookmarks.append({"time_s": minf(play_time, recording.current.summary.duration_s), "note": note.text.strip_edges() if note.text.strip_edges() != "" else "Review this step"})
	note.clear()
	render_events()
	app.projects.mark_dirty()

func remove_bookmark() -> void:
	var selected := events.get_selected()
	if selected and selected.get_metadata(0).has("bookmark_index"):
		recording.bookmarks.remove_at(selected.get_metadata(0).bookmark_index)
		render_events()
		app.projects.mark_dirty()

func clear_recording() -> void:
	playing = false
	recording = {}
	info = {}
	previous_recording = {}
	previous_info = {}
	imported = false
	play_time = 0
	badge.text = "Record a cycle to begin"
	metrics.text = "Simulated duration, phases and sampled TCP distance appear after recording."
	comparison.text = "Record the current recipe and optional baseline for comparison."
	current_caption.text = "CURRENT · RECORDED SIMULATION"
	baseline_panel.visible = false
	current_view.set_trace_path([], Palette.ACCENT)
	baseline_view.set_trace_path([], Palette.SUCCESS)
	current_view.apply_state(app.state)
	baseline_view.apply_state(app.state)
	events.clear()
	timeline.intervals = []
	timeline.baseline_intervals = []
	timeline.events = []
	timeline.bookmarks = []
	timeline.playhead = 0
	timeline.duration = 1
	timeline.set_samples([], [])
	slider.set_value_no_signal(0)
	clock.text = "0.0 / 0.0 s"
	details.text = "Scrub to inspect recorded robot, CNC and IO state."
	play_button.text = "Play"

func open_recording(path: String) -> void:
	if busy:
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > Archive.MAX_BYTES:
		app._failed("inspector.file", "FILE_LIMIT", "Recording unreadable or larger than 32 MiB")
		return
	var value: Variant = JSON.parse_string(file.get_as_text())
	var error := Archive.validate(value)
	if error != "":
		app._failed("inspector.file", "INVALID_RECORDING", error)
		return
	recording = value
	recording["bookmarks"] = recording.get("bookmarks", [])
	imported = true
	finish_load()

func save_recording(path: String) -> void:
	if busy or recording.is_empty():
		return
	var error := OK
	if save_csv:
		error = Archive.write_csv(path, recording)
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(recording))
			file.flush()
			error = file.get_error()
		else:
			error = FileAccess.get_open_error()
	if error != OK:
		app._failed("inspector.file", "WRITE_ERROR", "Cannot write the recording to the selected path")
	else:
		badge.text = "Saved locally · " + path.get_file()
