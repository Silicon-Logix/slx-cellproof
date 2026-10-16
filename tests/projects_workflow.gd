# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends SceneTree

const Storage = preload("res://project_storage.gd")
var app: Control
var checks := 0
var failed := false

func _initialize() -> void:
	run.call_deferred()

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("PROJECT FAIL: " + message)
		quit(1)

func response(operation: String) -> Dictionary:
	while true:
		var item: Array = await app.core.response
		if item[0] == operation:
			return item[1]
	return {}

func idle() -> void:
	while app.projects.busy or app.inspector.busy:
		await process_frame

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Project workflow timeout"); quit(1))
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await response("open")
	var projects: Node = app.projects
	expect(not projects.dirty, "new startup project is clean")
	app.core.request("baseline.save")
	await response("baseline.save")
	app.editor.text += "\n# Project persistence check"
	var saved_program: String = app.editor.text
	expect(projects.dirty and app.project_caption.text.contains("Unsaved"), "editor and baseline changes mark project dirty")
	app.pages.current_tab = 4
	app.inspector.begin_capture()
	await idle()
	app.inspector.seek(45)
	app.inspector.note.text = "Review this handoff"
	app.inspector.add_bookmark()
	var file: String = projects.base + "roundtrip.cellproof"
	projects.save_to(file)
	await idle()
	expect(FileAccess.file_exists(file) and not projects.dirty, "complete project saves to the selected file")
	var saved := Storage.read(file)
	expect(saved.has("data") and saved.data.workspace.baseline != null, "baseline is stored with recipe")
	expect(saved.data.recording.bookmarks.size() == 1, "recording and notes are stored")
	projects.new_project()
	await idle()
	expect(app.inspector.recording.is_empty() and not app.state.baseline_available, "New project clears reference and previous recording")
	projects.load_path(file)
	await idle()
	expect(app.editor.text == saved_program and app.state.baseline_available, "Open project restores program and reference through native transactions")
	expect(app.state.status == "idle" and app.state.simulated_time_s == 0, "opening never starts or resumes execution")
	expect(app.inspector.recording.bookmarks[0].note == "Review this handoff" and is_equal_approx(app.inspector.play_time, 45), "view, timeline and bookmarks round trip")
	expect(app.inspector.imported and app.inspector.badge.text.contains("UNVERIFIED"), "saved evidence has explicit local provenance")
	app.editor.text += "\n# Unsaved recovery content"
	projects.save_to(projects.recovery_path(), true)
	await idle()
	var recovery: String = projects.recovery_path()
	expect(projects.dirty and FileAccess.file_exists(recovery), "autosave preserves recovery without falsely marking the project saved")
	# Simulate an unclean application exit without the clean-close save dialog.
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await response("open")
	projects = app.projects
	projects.load_path(recovery, true)
	await idle()
	expect(app.editor.text.contains("Unsaved recovery content") and projects.dirty, "autosave recovers unsaved text as an idle dirty project")
	projects.save_to(file)
	await idle()
	expect(FileAccess.file_exists(file + ".backup"), "previous successful save retained")
	var broken := FileAccess.open(file, FileAccess.WRITE)
	broken.store_string("{corrupted")
	broken.close()
	var fallback := Storage.read(file)
	expect(fallback.has("data") and fallback.used_backup, "corrupt main file recovers from last valid backup")
	var impossible: Dictionary = saved.data.duplicate(true)
	impossible.settings.page = 99
	expect(Storage.validate(impossible) != "", "malformed project settings rejected before changing UI")
	var reached := false
	app.editor.text += "\n# Guard unsaved changes"
	projects.before_replacing(func(): reached = true)
	expect(projects.guard.visible and not reached, "dirty project is protected by Save / Discard / Cancel")
	projects.guard.hide()
	projects.pending_action = Callable()
	projects.refresh_recents()
	expect(projects.recent_menu.item_count > 0, "recent projects available")
	projects.autosave_interval = 0.05
	projects.autosave_elapsed = 0
	projects.last_autosave_revision = -1
	var deadline := Time.get_ticks_msec() + 3000
	while not FileAccess.file_exists(projects.recovery_path()) and Time.get_ticks_msec() < deadline:
		await process_frame
	await idle()
	expect(FileAccess.file_exists(projects.recovery_path()), "autosave timer commits recovery copies through the real core")
	app.backend_ready = false
	projects.request_quit()
	expect(projects.guard.visible, "the window can close safely even when the core is unavailable")
	projects.guard.hide()
	projects.pending_action = Callable()
	app.backend_ready = true
	var before_renewal: String = app.core.token
	var editor_before_renewal: String = app.editor.text
	app.core.request("session.renew")
	app.core.request("baseline.save")
	await response("session.renew")
	expect(app.core.token != before_renewal and app.editor.text == editor_before_renewal, "session renewal preserves unsaved editor content")
	await response("baseline.save")
	expect(app.state.status == "idle", "queued authorized operations use the renewed token")
	if not failed:
		print("PASS: %d project lifecycle GUI checks" % checks)
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
