# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends Node
## Product identity, local help and bundled legal documents.

const Palette = preload("res://slx_theme.gd")
const WEBSITE := "https://www.siliconlogix.it/"
const DOCUMENTS := {
	"guide": ["CellProof user guide", "res://content/user-guide.txt"],
	"api": ["SLX language and API reference", "res://content/api-reference.txt"],
	"license": ["Silicon LogiX Evaluation License 1.0", "res://content/license.txt"],
	"notices": ["Third-party licenses and credits", "res://content/third-party-notices.txt"]
}

var application: Control
var core_version := "Not connected"
var about_dialog: AcceptDialog
var document_dialog: AcceptDialog
var about_details: Label
var document_body: RichTextLabel
var current_document := ""

func attach(owner_control: Control) -> void:
	application = owner_control
	application.add_child(self)

func product_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "Unknown"))

func diagnostic_summary() -> Dictionary:
	# Deliberately omit paths, IP addresses, session tokens and recipe contents.
	return {"product": "SLX CellProof", "version": product_version(),
		"core_version": core_version, "core_connected": application.backend_ready,
		"godot_version": Engine.get_version_info().string, "platform": OS.get_name()}

func has_open_dialog() -> bool:
	return (is_instance_valid(about_dialog) and about_dialog.visible) or (is_instance_valid(document_dialog) and document_dialog.visible)

func _label(value: String, font_size: int, color: Color = Palette.INK) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

func _button(value: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = 38
	result.pressed.connect(action)
	return result

func show_about() -> void:
	if is_instance_valid(document_dialog):
		document_dialog.hide()
	if not is_instance_valid(about_dialog):
		about_dialog = AcceptDialog.new()
		about_dialog.name = "AboutCellProof"
		about_dialog.title = "About SLX CellProof"
		about_dialog.ok_button_text = "Close"
		about_dialog.min_size = Vector2i(680, 500)
		about_dialog.theme = application.theme
		application.add_child(about_dialog)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 16)
		var banner := PanelContainer.new()
		banner.add_theme_stylebox_override("panel", Palette.box(Palette.NAVY, 8))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/cellproof.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(76, 76)
		row.add_child(icon)
		var heading := VBoxContainer.new()
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var product_title := _label("SLX CellProof", 29, Palette.ON_DARK)
		product_title.autowrap_mode = TextServer.AUTOWRAP_OFF
		heading.add_child(product_title)
		heading.add_child(_label("PROGRAM  /  VERIFY  /  COMPARE", 11, Palette.DARK_MUTED))
		row.add_child(heading)
		var version_label := _label("v" + product_version(), 17, Palette.ON_DARK)
		version_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		version_label.custom_minimum_size.x = 80
		version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(version_label)
		banner.add_child(row)
		column.add_child(banner)
		column.add_child(_label("Local programming and change verification for a UR5e-CNC demonstration workcell.", 16))
		about_details = _label("", 14)
		column.add_child(about_details)
		column.add_child(HSeparator.new())
		column.add_child(_label("Silicon LogiX Evaluation License 1.0", 15))
		column.add_child(_label("Study and business evaluation are permitted under the included license. Third-party components retain their own terms.", 13, Palette.MUTED))
		var legal := HBoxContainer.new()
		legal.add_child(_button("License", func(): show_document("license")))
		legal.add_child(_button("Third-party notices", func(): show_document("notices")))
		legal.add_child(_button("User guide", func(): show_document("guide")))
		column.add_child(legal)
		var links := HBoxContainer.new()
		links.add_child(_button("Silicon LogiX website", func(): OS.shell_open(WEBSITE)))
		links.add_child(_button("Copy system info", func(): DisplayServer.clipboard_set(JSON.stringify(diagnostic_summary(), "  "))))
		column.add_child(links)
		column.add_child(_label("Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).", 12, Palette.MUTED))
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.add_child(column)
		about_dialog.add_child(scroll)
	var details := "AUTHOR          Marco Pezzullo / Silicon LogiX\nVERSION         " + product_version()
	details += "\nTECHNOLOGY      Godot " + Engine.get_version_info().string + " / native C++20 core"
	details += "\nCORE            " + core_version + (" / connected" if application.backend_ready else " / unavailable")
	details += "\nPLATFORM        " + OS.get_name() + "\nDATA            Local recipes and reports; no account required"
	about_details.text = details
	about_dialog.popup_centered_clamped(Vector2i(760, 640), 0.9)

func _escape(value: String) -> String:
	return value.replace("[", "\u0001").replace("]", "[rb]").replace("\u0001", "[lb]")

func _format_document(value: String, reflow: bool = false) -> String:
	if reflow:
		var lines: Array[String] = []
		var paragraph := ""
		var inside_code := false
		for line in value.split("\n"):
			var structural := line.is_empty() or line.begins_with("#") or line.begins_with("|") or line.begins_with("- ") or line.begins_with("```") or line.begins_with("<!--") or line.begins_with("-->")
			if structural or inside_code:
				if paragraph != "":
					lines.append(paragraph)
					paragraph = ""
				lines.append(line)
			else:
				paragraph += (" " if paragraph != "" else "") + line.strip_edges()
			if line.begins_with("```"):
				inside_code = not inside_code
		if paragraph != "":
			lines.append(paragraph)
		value = "\n".join(lines)
	var output := ""
	var comment := false
	var code := false
	var bold := RegEx.new()
	bold.compile("\\*\\*(.+?)\\*\\*")
	var link := RegEx.new()
	link.compile("\\[([^\\]]+)\\]\\([^)]+\\)")
	for line in value.split("\n"):
		if line.begins_with("<!--"):
			comment = true
		if comment:
			if line.contains("-->"):
				comment = false
			continue
		if line.begins_with("```"):
			code = not code
			output += "[code]" if code else "[/code]\n"
			continue
		var escaped := _escape(link.sub(line, "$1", true) if not code else line)
		if not code:
			escaped = bold.sub(escaped, "[b]$1[/b]", true)
			if line.begins_with("# "):
				escaped = "[font_size=25][b]" + _escape(line.substr(2)) + "[/b][/font_size]"
			elif line.begins_with("## "):
				escaped = "[font_size=19][b]" + _escape(line.substr(3)) + "[/b][/font_size]"
			elif line.begins_with("- "):
				escaped = "• " + escaped.substr(2)
		output += escaped + "\n"
	if code:
		output += "[/code]"
	return output

func show_document(kind: String) -> void:
	if not DOCUMENTS.has(kind):
		return
	if is_instance_valid(about_dialog):
		about_dialog.hide()
	if not is_instance_valid(document_dialog):
		document_dialog = AcceptDialog.new()
		document_dialog.name = "CellProofDocument"
		document_dialog.ok_button_text = "Close"
		document_dialog.theme = application.theme
		document_dialog.min_size = Vector2i(640, 440)
		application.add_child(document_dialog)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 12)
		document_body = RichTextLabel.new()
		document_body.name = "DocumentBody"
		document_body.bbcode_enabled = true
		document_body.selection_enabled = true
		document_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		document_body.custom_minimum_size = Vector2(600, 430)
		column.add_child(document_body)
		column.add_child(_button("Copy document", func(): DisplayServer.clipboard_set(current_document)))
		document_dialog.add_child(column)
	current_document = FileAccess.get_file_as_string(DOCUMENTS[kind][1])
	if current_document.is_empty():
		current_document = "This document is missing. Reinstall the complete CellProof package."
	document_dialog.title = DOCUMENTS[kind][0]
	document_body.text = _format_document(current_document, kind in ["guide", "api"])
	document_body.scroll_to_line(0)
	document_dialog.popup_centered_clamped(Vector2i(940, 650), 0.9)
