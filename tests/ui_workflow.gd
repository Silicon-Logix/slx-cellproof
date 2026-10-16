# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends SceneTree
## Exercise interaction, contrast, keyboard protection and responsive container bounds.

var app: Control
var checks := 0
var failed := false

func _initialize() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("UI FAIL: " + message)
		quit(1)

func hover(button: Button) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)
	await process_frame
	if not button.is_hovered():
		root.notify_mouse_entered()
		root.push_input(motion, true)
		await process_frame

func contrast(a: Color, b: Color) -> float:
	var first := a.srgb_to_linear().get_luminance()
	var second := b.srgb_to_linear().get_luminance()
	return (maxf(first, second) + 0.05) / (minf(first, second) + 0.05)

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("UI workflow timeout"); quit(1))
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.screenshot_done = true
	await app.core.response
	for dimensions in [Vector2i(1200, 760), Vector2i(1560, 960), Vector2i(1920, 1080)]:
		root.size = dimensions
		for page in [0, 4, 1, 2, 3]:
			app.pages.current_tab = page
			await process_frame
			await process_frame
			var frame: Rect2 = app.pages.get_global_rect()
			var bounds: Rect2 = app.get_global_rect()
			expect(frame.end.x <= bounds.end.x + 1 and frame.end.y <= bounds.end.y + 1, "workspace remains within the window at %s, page %d" % [dimensions, page])
	root.size = Vector2i(1440, 900)
	app.pages.current_tab = 4
	await process_frame
	await process_frame
	for button in [app.inspector.compare, app.inspector.trail]:
		for selected in [false, true]:
			button.set_pressed_no_signal(selected)
			await hover(button)
			expect(button.is_hovered() and button.button_pressed == selected, "mouse hover preserves the actual toggle state")
			var role := "hover_pressed" if selected else "hover"
			var style: StyleBox = button.get_theme_stylebox(role)
			var color: Color = button.get_theme_color("font_" + role + "_color")
			expect(style is StyleBoxFlat and contrast(color, style.bg_color) >= 4.5, "selected and unselected hover text remain readable")
		button.grab_focus()
		expect(button.has_focus(), "toggles support visible keyboard focus")
	for button in app.find_children("*", "Button", true, false):
		if button.text in ["Record cycle", "■ STOP", "Help", "Project"]:
			for role in ["normal", "hover", "pressed", "hover_pressed"]:
				var color_role: String = "font_color" if role == "normal" else "font_" + role + "_color"
				var style: StyleBox = button.get_theme_stylebox(role)
				expect(style is StyleBoxFlat and contrast(button.get_theme_color(color_role), style.bg_color) >= 4.5, "primary and dark-header action contrast: %s / %s" % [button.text, role])
	app.editor.text += "\n# Unsaved keyboard protection"
	var text: String = app.editor.text
	var key := InputEventKey.new()
	key.ctrl_pressed = true
	key.keycode = KEY_N
	key.pressed = true
	app._unhandled_key_input(key)
	expect(app.projects.guard.visible, "Ctrl+N protects unsaved work")
	key.keycode = KEY_S
	app._unhandled_key_input(key)
	expect(not app.projects.save_dialog.visible and app.editor.text == text, "modal confirmation blocks background document shortcuts")
	app.projects.guard.canceled.emit()
	app.projects.guard.hide()
	key.keycode = KEY_S
	key.shift_pressed = true
	app._unhandled_key_input(key)
	expect(app.projects.save_dialog.visible, "Ctrl+Shift+S opens project Save As")
	app.projects.save_dialog.hide()
	app.core.request("validate", {"text": "UNSUPPORTED"})
	await app.core.failed
	expect(app.error_dialog.visible and app.error_dialog.dialog_text.contains("Line 1"), "native validation errors have a readable source-line diagnostic")
	app.error_dialog.get_ok_button().pressed.emit()
	expect(not app.error_dialog.visible, "the diagnostic Close action returns control to the workspace")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/ui-qa-050.png"))
	print("PASS: %d desktop interaction and layout checks" % checks)
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
