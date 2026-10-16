# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends SceneTree
## Exercise the distributed application, including offline help and legal access.

var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("PRODUCT SMOKE FAIL: " + message)
		quit(1)

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Product smoke test timeout"); quit(1))
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await app.core.response
	expect(app.backend_ready, "native core starts")
	var dialogs: Node = app.product_dialogs
	expect(dialogs.core_version == dialogs.product_version(), "product and core versions agree")
	var about: Button
	for button in app.find_children("*", "Button", true, false):
		if button.text == "About":
			about = button
	expect(about != null, "About action exists")
	if about == null:
		return
	about.pressed.emit()
	expect(dialogs.about_dialog.visible, "About action opens the dialog")
	expect(dialogs.about_details.text.contains("Marco Pezzullo") and dialogs.about_details.text.contains(dialogs.core_version), "About includes author and actual core version")
	dialogs.show_document("license")
	expect(dialogs.document_dialog.visible and dialogs.current_document.contains("SILICON LOGIX EVALUATION LICENSE 1.0"), "full evaluation license is available offline")
	dialogs.show_document("notices")
	expect(dialogs.current_document.contains("Godot Engine") and dialogs.current_document.contains("Permission is hereby granted"), "complete upstream terms are bundled")
	expect(dialogs.current_document.contains("Redistribution and use in source and binary forms"), "UR BSD terms are available")
	dialogs.show_document("guide")
	expect(dialogs.current_document.contains("Ctrl+S") and dialogs.current_document.contains("Verify change"), "guide documents actual actions and shortcuts")
	expect(dialogs.document_body.get_parsed_text().length() > 300 and dialogs.document_body.get_theme_color("default_color").get_luminance() < 0.3, "guide renders readable dark text on its light surface")
	dialogs.show_document("api")
	expect(dialogs.current_document.contains("slx.cellproof/v1"), "API reference is available offline")
	var info: Dictionary = dialogs.diagnostic_summary()
	expect(info.size() == 6 and not info.has("session") and not info.has("ip") and not info.has("program"), "copied system info excludes connection and recipe data")
	dialogs.document_dialog.hide()
	var key := InputEventKey.new()
	key.keycode = KEY_F12
	key.pressed = true
	app._unhandled_key_input(key)
	expect(dialogs.about_dialog.visible, "F12 opens About")
	dialogs.about_dialog.hide()
	key.keycode = KEY_F1
	app._unhandled_key_input(key)
	expect(dialogs.document_dialog.visible and dialogs.document_dialog.title == "CellProof user guide", "F1 opens the guide")
	dialogs.document_dialog.hide()
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/advanced-services.json"))
	expect(catalogue.services.size() == 5 and catalogue.services[0].status == "on_request", "scoped advanced-services catalogue is bundled")
	app.core.request("baseline.save")
	while true:
		var response: Array = await app.core.response
		if response[0] == "baseline.save":
			break
	app.pages.current_tab = 4
	var inspector: VBoxContainer = app.inspector
	inspector.capture_button.pressed.emit()
	while inspector.busy:
		await process_frame
	expect(not inspector.recording.is_empty() and inspector.recording.current.frames.size() > 1000, "Cycle Inspector records through the distributed core")
	if inspector.recording.is_empty():
		quit(1)
		return
	expect(inspector.recording.baseline != null and inspector.recording.first_difference == null, "inspector compares the recorded baseline")
	var joints: Array = app.state.joints_rad.duplicate()
	inspector.seek(40)
	expect(is_equal_approx(inspector.play_time, 40) and app.state.joints_rad == joints, "replay is isolated from the open cell")
	expect(inspector.frame_at("current", 40).io.has("machine_ready"), "recording includes sampled IO")
	expect(load("res://inspector_archive.gd").validate(inspector.recording) == "", "recording satisfies the portable archive contract")
	if failed:
		quit(1)
	else:
		print("SLX_PRODUCT_SMOKE_OK: %d assertions" % checks)
		quit()
