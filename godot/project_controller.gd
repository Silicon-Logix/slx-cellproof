# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends Node
## Project lifecycle and bounded, transactional communication with the product core.

const Storage = preload("res://project_storage.gd")
var app: Control
var path := ""
var disk_sha256 := ""
var project_id := ""
var instance_id := ""
var base := "user://"
var dirty := false
var revision := 0
var saved_revision := 0
var busy := false
var mode := ""
var initialized := false
var core_ready := false
var autosave_enabled := true
var autosave_interval := 30.0
var autosave_elapsed := 0.0
var last_autosave_revision := -1
var preferences: Dictionary = {}
var pending_document: Dictionary = {}
var pending_path := ""
var transfer := PackedByteArray()
var transfer_offset := 0
var transaction := ""
var pending_action: Callable
var recent_menu: PopupMenu
var menu: MenuButton
var open_dialog: FileDialog
var save_dialog: FileDialog
var guard: ConfirmationDialog
var recovery_dialog: AcceptDialog
var recovery_list: ItemList
var recovery_paths: Array[String] = []
var settings_dialog: AcceptDialog
var status := ""
var loading_overlay: Control

func make_menu(owner_app: Control) -> MenuButton:
	app = owner_app
	menu = MenuButton.new()
	menu.text = "Project"
	menu.custom_minimum_size.y = 38
	for role in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		menu.add_theme_color_override(role, Color("e8edf8"))
	menu.add_theme_stylebox_override("normal", app._box(Color("111c31"), 6, Color("35435a")))
	for role in ["hover", "pressed", "hover_pressed"]:
		menu.add_theme_stylebox_override(role, app._box(Color("283954"), 6, Color("35435a")))
	var popup := menu.get_popup()
	for item in [["New project", 0], ["Open project…  Ctrl+O", 1], ["Save project  Ctrl+S", 2], ["Save project as…  Ctrl+Shift+S", 3]]:
		popup.add_item(item[0], item[1])
	recent_menu = PopupMenu.new()
	recent_menu.name = "RecentProjects"
	popup.add_child(recent_menu)
	popup.add_submenu_item("Recent projects", "RecentProjects", 4)
	popup.add_item("Recover autosave…", 5)
	popup.add_item("Restore previous save…", 6)
	popup.add_item("Project settings…", 7)
	popup.add_item("Renew demo session", 9)
	popup.add_separator()
	popup.add_item("Quit", 8)
	popup.id_pressed.connect(_menu_action)
	popup.about_to_popup.connect(refresh_recents)
	recent_menu.id_pressed.connect(func(index: int):
		var recent: Array = preferences.get("recent", [])
		if index >= 0 and index < recent.size():
			var selected: String = recent[index]
			before_replacing(func(): load_path(selected)))
	return menu

func _menu_action(id: int) -> void:
	match id:
		0: before_replacing(new_project)
		1: before_replacing(func(): open_dialog.popup_centered_ratio(0.72))
		2: save_project()
		3: save_project(true)
		5: show_recovery()
		6:
			if path != "" and FileAccess.file_exists(path + ".backup"):
				before_replacing(func(): load_path(path + ".backup"))
		7: show_settings()
		8: request_quit()
		9:
			if ready_for_document():
				app.core.request("session.renew", {"profile": "demo-ur5e-cnc-v1"})

func setup() -> void:
	instance_id = Crypto.new().generate_random_bytes(8).hex_encode()
	project_id = Crypto.new().generate_random_bytes(16).hex_encode()
	# Automated tools get isolated storage and never open a user's recovery prompt.
	if "--script" in OS.get_cmdline_args() or "--smoke" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args():
		base = "user://checks/" + str(OS.get_process_id()) + "/"
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + "settings.json")) if FileAccess.file_exists(base + "settings.json") else {}
	preferences = value if value is Dictionary else {}
	autosave_enabled = preferences.get("autosave_enabled", true) == true
	var interval: Variant = preferences.get("autosave_interval_s", 30)
	autosave_interval = clampf(float(interval), 15, 600) if interval is int or interval is float else 30
	open_dialog = FileDialog.new()
	open_dialog.title = "Open CellProof project · restores an idle simulation"
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_dialog.filters = PackedStringArray(["*.cellproof ; Complete CellProof project"])
	open_dialog.file_selected.connect(load_path)
	app.add_child(open_dialog)
	save_dialog = FileDialog.new()
	save_dialog.title = "Save complete CellProof project"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.filters = PackedStringArray(["*.cellproof ; Recipe, baseline, recording and project settings"])
	save_dialog.file_selected.connect(func(selected: String): save_to(selected, false, true))
	save_dialog.canceled.connect(func(): pending_action = Callable())
	app.add_child(save_dialog)
	guard = ConfirmationDialog.new()
	guard.title = "Unsaved project changes"
	guard.dialog_text = "Save this project's changes before continuing?"
	guard.ok_button_text = "Save"
	guard.add_button("Discard", true, "discard")
	guard.confirmed.connect(func(): save_project())
	guard.canceled.connect(func(): pending_action = Callable())
	guard.custom_action.connect(func(action: String):
		if action == "discard":
			guard.hide()
			run_pending())
	app.add_child(guard)
	recovery_dialog = AcceptDialog.new()
	recovery_dialog.title = "Recover a local project autosave"
	recovery_dialog.min_size = Vector2i(720, 350)
	recovery_dialog.ok_button_text = "Close"
	var content: VBoxContainer = app._vbox(10)
	app._note(content, "Autosaves are local. Recovery restores recipes and recorded simulation, then leaves the cell idle.")
	recovery_list = ItemList.new()
	recovery_list.custom_minimum_size = Vector2(650, 220)
	content.add_child(recovery_list)
	content.add_child(app._button("Recover selected", func():
		var selected := recovery_list.get_selected_items()
		if not selected.is_empty():
			var selected_path := recovery_paths[selected[0]]
			recovery_dialog.hide()
			before_replacing(func(): load_path(selected_path, true)), true))
	content.add_child(app._button("Delete selected autosave", func():
		var selected := recovery_list.get_selected_items()
		if not selected.is_empty() and selected[0] < recovery_paths.size():
			var selected_path := recovery_paths[selected[0]]
			for suffix in ["", ".backup"]:
				var candidate: String = selected_path + suffix
				if FileAccess.file_exists(candidate):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
			last_autosave_revision = -1
			show_recovery()))
	recovery_dialog.add_child(app._margin(content, 16))
	app.add_child(recovery_dialog)
	app.get_tree().auto_accept_quit = false
	app.get_window().close_requested.connect(request_quit)
	app.inspector.part.item_selected.connect(func(_index: int): mark_dirty())
	app.inspector.fault.item_selected.connect(func(_index: int): mark_dirty())
	app.inspector.compare.toggled.connect(func(_selected: bool): mark_dirty())
	for toggle in [app.inspector.trail, app.inspector.guards_toggle, app.guards_toggle, app.markers_toggle]:
		toggle.toggled.connect(func(_selected: bool): mark_dirty())
	for selector in [app.simulation_rate_select, app.inspector.speed_select]:
		selector.item_selected.connect(func(_selected: int): mark_dirty())
	for view in [app.cell_view, app.inspector.current_view, app.inspector.baseline_view]:
		view.camera_changed.connect(mark_dirty)
	loading_overlay = Control.new()
	loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	loading_overlay.focus_mode = Control.FOCUS_ALL
	loading_overlay.gui_input.connect(func(_event: InputEvent): app.get_viewport().set_input_as_handled())
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.953, 0.961, 0.976, 0.95)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_overlay.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(app._label("Opening project…  ·  The simulation will remain idle", 22))
	loading_overlay.add_child(center)
	loading_overlay.visible = false
	app.add_child(loading_overlay)
	initialized = true
	update_title()

func core_opened() -> void:
	core_ready = true
	for argument in OS.get_cmdline_user_args():
		if argument.to_lower().ends_with(".cellproof") and FileAccess.file_exists(argument):
			load_path(argument)
			return
	if base == "user://" and not find_recovery().is_empty():
		show_recovery.call_deferred()

func mark_dirty() -> void:
	if not initialized or not core_ready or mode == "loading" or mode == "new":
		return
	revision += 1
	dirty = true
	update_title()

func update_title() -> void:
	if not is_instance_valid(app.project_caption):
		return
	var title := path.get_file() if path != "" else "Untitled project"
	app.project_caption.text = title + (" · Unsaved" if dirty else "")
	app.project_caption.tooltip_text = (path if path != "" else "Save a complete project from the Project menu") + ("\n" + status if status != "" else "")
	app.get_window().title = title + (" *" if dirty else "") + " — SLX CellProof"

func ready_for_document() -> bool:
	if not app.backend_ready or busy or app.campaign_busy or app.inspector.busy or app.pending_action != "":
		return false
	return true

func before_replacing(action: Callable) -> void:
	if not ready_for_document():
		return
	pending_action = action
	if dirty:
		guard.popup_centered()
	else:
		run_pending()

func run_pending() -> void:
	var action := pending_action
	pending_action = Callable()
	if action.is_valid():
		action.call()

func save_project(save_as: bool = false) -> void:
	if not app.backend_ready:
		app._failed("project.save", "CORE_UNAVAILABLE", "The core is unavailable. Existing recovery copies are preserved; the editor text can still be copied.")
		return
	if not ready_for_document():
		return
	if save_as or path == "":
		save_dialog.current_file = path.get_file() if path != "" else "Untitled.cellproof"
		save_dialog.popup_centered_ratio(0.72)
	else:
		save_to(path)

func save_to(selected: String, autosave: bool = false, overwrite_confirmed: bool = false) -> void:
	if not ready_for_document():
		return
	if not autosave and not overwrite_confirmed and selected == path and disk_sha256 != "" and FileAccess.file_exists(path) and FileAccess.get_sha256(path) != disk_sha256:
		app._failed("project.save", "FILE_CHANGED", "The project changed on disk. Use Save project as to preserve both versions.")
		return
	pending_path = selected if selected.to_lower().ends_with(".cellproof") else selected + ".cellproof"
	mode = "autosave" if autosave else "saving"
	busy = true
	saved_revision = revision
	app.core.request("project.export")

func settings_snapshot() -> Dictionary:
	return {"page": app.pages.current_tab, "pendant": app.pendant_pages.current_tab,
		"inspector_part": app.inspector.part.selected, "inspector_fault": app.inspector.fault.selected,
		"compare_baseline": app.inspector.compare.button_pressed, "replay_time_s": app.inspector.play_time,
		"replay_speed": app.inspector.speed, "simulation_rate": app.playback_rate,
		"show_trail": app.inspector.trail.button_pressed, "show_guards": app.inspector.guards_toggle.button_pressed,
		"show_cell_guards": app.guards_toggle.button_pressed, "show_points": app.markers_toggle.button_pressed,
		"camera": [app.cell_view.angle, app.cell_view.elevation, app.cell_view.distance],
		"inspector_camera": [app.inspector.current_view.angle, app.inspector.current_view.elevation, app.inspector.current_view.distance],
		"baseline_camera": [app.inspector.baseline_view.angle, app.inspector.baseline_view.elevation, app.inspector.baseline_view.distance]}

func document(workspace: Dictionary) -> Dictionary:
	var current := workspace.duplicate(true)
	current.recipe.program = app.editor.text
	return {"schema": Storage.SCHEMA, "project_id": project_id,
		"saved_utc": Time.get_datetime_string_from_system(true), "product_version": str(ProjectSettings.get_setting("application/config/version")),
		"origin_path": path, "workspace": current, "settings": settings_snapshot(),
		"recording": app.inspector.recording if not app.inspector.recording.is_empty() else null,
		"report": app.report if not app.report.is_empty() else null}

func handle_response(operation: String, result: Dictionary) -> void:
	if operation == "project.export" and mode in ["saving", "autosave"]:
		var data := document(result)
		var prepared := Storage.prepare(pending_path, data)
		if prepared.has("error"):
			app._failed("project.save", "WRITE_ERROR", "Cannot save project; the previous file is preserved. " + prepared.error)
			return
		app.core.request("project.file.commit", prepared)
	elif operation == "project.file.commit" and mode in ["saving", "autosave"]:
		var was_autosave := mode == "autosave"
		busy = false
		mode = ""
		if was_autosave:
			last_autosave_revision = saved_revision
			status = "Autosaved locally at " + Time.get_time_string_from_system()
			var labels: Dictionary = preferences.get("recovery_labels", {}) if preferences.get("recovery_labels") is Dictionary else {}
			if labels.size() < 100 or labels.has(project_id):
				labels[project_id] = path.get_file() if path != "" else "Untitled project"
				preferences["recovery_labels"] = labels
				save_preferences()
		else:
			path = pending_path
			disk_sha256 = FileAccess.get_sha256(path)
			dirty = revision != saved_revision
			remember_path(path)
			status = "Project saved locally"
			remove_own_recovery()
		update_title()
		if not was_autosave:
			if dirty and pending_action.is_valid():
				guard.popup_centered()
			else:
				run_pending()
	elif operation == "project.begin" and mode == "loading":
		transaction = result.transaction
		send_chunk()
	elif operation == "project.stage" and mode == "loading":
		transfer_offset = int(result.next_offset)
		send_chunk()
	elif operation in ["project.commit", "project.new"]:
		if mode != "loading" or pending_path != recovery_path():
			remove_own_recovery()
		if mode == "loading":
			var data := pending_document
			project_id = data.project_id
			path = "" if data.get("autosave_recovery", false) else pending_path
			disk_sha256 = FileAccess.get_sha256(path) if path != "" else ""
			restore_settings(data.settings)
			if data.get("recording") != null:
				app.inspector.recording = data.recording
				app.inspector.imported = true
				app.inspector.finish_load()
				app.inspector.seek(data.settings.replay_time_s)
			if data.get("report") != null:
				app.report = data.report
				app._render_report()
				app.report_label.text += " · saved local evidence, unverified"
			dirty = data.get("recovered", false)
			if path != "":
				remember_path(path)
			status = "Recovered local autosave" if dirty else "Project opened · local simulation idle"
		else:
			path = ""
			disk_sha256 = ""
			project_id = Crypto.new().generate_random_bytes(16).hex_encode()
			dirty = false
			status = "New project · local simulation idle"
			restore_settings({"page": 0, "pendant": 0, "inspector_part": 0, "inspector_fault": 0,
				"compare_baseline": true, "replay_speed": 1.0, "simulation_rate": 1.0,
				"camera": [-2.3, 0.46, 4.8], "inspector_camera": [-2.3, 0.46, 4.8]})
		busy = false
		mode = ""
		revision += 1
		last_autosave_revision = -1
		transfer = PackedByteArray()
		pending_document = {}
		update_title()
	elif operation in ["configuration.set", "point.update", "point.teach", "baseline.save", "campaign.run", "recipe.import"]:
		mark_dirty()

func load_path(selected: String, recovered: bool = false) -> void:
	if not ready_for_document():
		return
	if app.state.get("status", "") in ["running", "paused"] or app.monitor_connected:
		app._failed("project.open", "BUSY", "Stop the simulation and disconnect the controller monitor before opening a project")
		return
	var result := Storage.read(selected)
	if result.has("error"):
		app._failed("project.open", "INVALID_PROJECT", result.error)
		return
	pending_document = result.data
	pending_document["recovered"] = recovered or result.used_backup or selected.ends_with(".backup")
	pending_document["autosave_recovery"] = recovered
	pending_path = selected.trim_suffix(".backup")
	transfer = JSON.stringify(pending_document.workspace).to_utf8_buffer()
	transfer_offset = 0
	busy = true
	mode = "loading"
	app.core.request("project.begin", {"size_bytes": transfer.size(), "sha256": transfer.get_string_from_utf8().sha256_text()})

func send_chunk() -> void:
	if transfer_offset == transfer.size():
		app.core.request("project.commit", {"transaction": transaction})
	else:
		var end := mini(transfer_offset + 4096, transfer.size())
		app.core.request("project.stage", {"transaction": transaction, "offset": transfer_offset, "chunk_hex": transfer.slice(transfer_offset, end).hex_encode()})

func new_project() -> void:
	if not ready_for_document():
		return
	busy = true
	mode = "new"
	app.core.request("project.new")

func operation_failed(operation: String, message: String) -> void:
	if operation.begins_with("project.") or operation in ["transport", "startup"]:
		busy = false
		mode = ""
		transfer = PackedByteArray()
		pending_document = {}
		pending_action = Callable()
		status = message
		update_title()

func restore_settings(settings: Dictionary) -> void:
	app.pages.current_tab = int(settings.page)
	app.pendant_pages.current_tab = int(settings.pendant)
	app.playback_rate = settings.simulation_rate
	app.simulation_rate_select.select([1.0, 2.0, 5.0].find(float(settings.simulation_rate)))
	app.inspector.part.select(int(settings.inspector_part))
	app.inspector.fault.select(int(settings.inspector_fault))
	app.inspector.compare.set_pressed_no_signal(settings.compare_baseline)
	app.inspector.speed = settings.replay_speed
	app.inspector.speed_select.select([0.25, 0.5, 1.0, 2.0, 5.0].find(float(settings.replay_speed)))
	app.inspector.trail.set_pressed_no_signal(settings.get("show_trail", true))
	app.inspector.guards_toggle.set_pressed_no_signal(settings.get("show_guards", false))
	app.guards_toggle.set_pressed_no_signal(settings.get("show_cell_guards", false))
	app.markers_toggle.set_pressed_no_signal(settings.get("show_points", false))
	app.inspector.current_view.trace.visible = app.inspector.trail.button_pressed
	app.inspector.baseline_view.trace.visible = app.inspector.trail.button_pressed
	app.inspector.current_view.set_guards(app.inspector.guards_toggle.button_pressed)
	app.inspector.baseline_view.set_guards(app.inspector.guards_toggle.button_pressed)
	app.cell_view.set_guards(app.guards_toggle.button_pressed)
	app.cell_view.markers.visible = app.markers_toggle.button_pressed
	for pair in [[app.cell_view, settings.camera], [app.inspector.current_view, settings.inspector_camera], [app.inspector.baseline_view, settings.get("baseline_camera", settings.inspector_camera)]]:
		pair[0].angle = pair[1][0]
		pair[0].elevation = clampf(pair[1][1], 0.05, 1.25)
		pair[0].distance = clampf(pair[1][2], 1.4, 9)
		pair[0]._update_camera()

func recovery_path() -> String:
	return base + "recovery/" + project_id + "-" + instance_id + ".cellproof"

func remove_own_recovery() -> void:
	for suffix in ["", ".backup"]:
		var target: String = recovery_path() + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target))

func find_recovery() -> Array[String]:
	var result: Array[String] = []
	var folder := DirAccess.open(base + "recovery")
	if folder:
		for file in folder.get_files():
			if file.ends_with(".cellproof"):
				result.append(base + "recovery/" + file)
	result.sort_custom(func(a: String, b: String): return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	return result

func show_recovery() -> void:
	recovery_list.clear()
	recovery_paths = find_recovery()
	for selected in recovery_paths:
		var labels: Dictionary = preferences.get("recovery_labels", {}) if preferences.get("recovery_labels") is Dictionary else {}
		var title: String = str(labels.get(selected.get_file().split("-")[0], "Project " + selected.get_file().substr(0, 8))).left(100)
		var label := title + " · " + Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(selected)) + " UTC"
		recovery_list.add_item(label)
	if recovery_paths.is_empty():
		recovery_list.add_item("No recoverable autosaves found")
		recovery_list.set_item_disabled(0, true)
	recovery_dialog.popup_centered()

func remember_path(selected: String) -> void:
	var recent: Array = preferences.get("recent", []) if preferences.get("recent") is Array else []
	recent.erase(selected)
	recent.push_front(selected)
	preferences["recent"] = recent.slice(0, 10)
	save_preferences()

func refresh_recents() -> void:
	recent_menu.clear()
	var recent: Array = preferences.get("recent", []) if preferences.get("recent") is Array else []
	for i in range(recent.size()):
		if recent[i] is String:
			recent_menu.add_item(recent[i].get_file(), i)
			recent_menu.set_item_tooltip(recent_menu.item_count - 1, recent[i])
	if recent_menu.item_count == 0:
		recent_menu.add_item("No recent projects")
		recent_menu.set_item_disabled(0, true)

func save_preferences() -> void:
	preferences["autosave_enabled"] = autosave_enabled
	preferences["autosave_interval_s"] = autosave_interval
	Storage.atomic_text(base + "settings.json", JSON.stringify(preferences), false)

func show_settings() -> void:
	if is_instance_valid(settings_dialog):
		settings_dialog.queue_free()
	settings_dialog = AcceptDialog.new()
	settings_dialog.title = "Project settings"
	settings_dialog.min_size = Vector2i(520, 200)
	var content: VBoxContainer = app._vbox(12)
	var enabled := CheckButton.new()
	enabled.text = "Autosave local recovery copies"
	enabled.button_pressed = autosave_enabled
	enabled.toggled.connect(func(value: bool): autosave_enabled = value; save_preferences())
	content.add_child(enabled)
	var interval := SpinBox.new()
	interval.min_value = 15
	interval.max_value = 600
	interval.step = 15
	interval.value = autosave_interval
	interval.suffix = "seconds"
	interval.value_changed.connect(func(value: float): autosave_interval = value; save_preferences())
	content.add_child(interval)
	app._note(content, "Projects include recipes, baseline, selected scenario, views, recorded cycles and saved verification evidence. Opening a project never starts motion.")
	settings_dialog.add_child(app._margin(content, 20))
	app.add_child(settings_dialog)
	settings_dialog.popup_centered()

func has_open_dialog() -> bool:
	return (open_dialog != null and open_dialog.visible) or (save_dialog != null and save_dialog.visible) or (guard != null and guard.visible) or (recovery_dialog != null and recovery_dialog.visible) or (is_instance_valid(settings_dialog) and settings_dialog.visible)

func request_quit() -> void:
	if busy:
		return
	pending_action = func(): remove_own_recovery(); app.get_tree().quit()
	if dirty:
		guard.popup_centered()
	else:
		run_pending()

func _process(delta: float) -> void:
	if is_instance_valid(loading_overlay):
		var opening := busy and mode in ["loading", "new"]
		if opening and not loading_overlay.visible:
			loading_overlay.grab_focus()
		loading_overlay.visible = opening
	if not initialized or not autosave_enabled or not dirty or revision == last_autosave_revision:
		return
	autosave_elapsed += delta
	if autosave_elapsed >= autosave_interval and ready_for_document():
		autosave_elapsed = 0
		save_to(recovery_path(), true)
