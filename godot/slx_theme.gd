# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends RefCounted
## Desktop palette shared with the SLX RadioTwin and OrbitLab product family.

const ACCENT := Color("5354e8")
const CANVAS := Color("f3f5f9")
const INK := Color("192541")
const LINE := Color("e3e8f0")
const MUTED := Color("56647a")
const NAVY := Color("111c31")
const PANEL := Color.WHITE
const SUCCESS := Color("087762")
const FAILURE := Color("b4484e")
const ATTENTION := Color("9b691b")
const HOVER := Color("f0f2fc")
const SELECTED := Color("e7e9fc")
const ON_DARK := Color("e8edf8")
const DARK_MUTED := Color("a8b6d0")

static func box(color: Color, radius: int = 6, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.border_color = border
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func create() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "Arial"])
	result.default_font = font
	result.default_font_size = 14
	for kind in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "CodeEdit", "Tree", "ItemList", "RichTextLabel", "PopupMenu"]:
		result.set_color("font_color", kind, INK)
		result.set_color("font_hover_color", kind, INK)
		result.set_color("font_hover_pressed_color", kind, INK)
		result.set_color("font_pressed_color", kind, INK)
		result.set_color("font_focus_color", kind, INK)
		result.set_color("font_disabled_color", kind, Color("99a4b9"))
		result.set_color("font_selected_color", kind, INK)
		result.set_color("font_outline_color", kind, Color.TRANSPARENT)
	for kind in ["Button", "OptionButton"]:
		result.set_stylebox("normal", kind, box(PANEL, 6, LINE))
		result.set_stylebox("hover", kind, box(HOVER, 6, Color("bcc2ef")))
		result.set_stylebox("pressed", kind, box(SELECTED, 6, ACCENT))
		result.set_stylebox("hover_pressed", kind, box(SELECTED, 6, ACCENT))
		result.set_stylebox("disabled", kind, box(CANVAS, 6, LINE))
		result.set_stylebox("focus", kind, box(Color.TRANSPARENT, 6, ACCENT))
	for kind in ["LineEdit", "TextEdit", "CodeEdit", "Tree"]:
		result.set_stylebox("normal", kind, box(PANEL, 6, LINE))
		result.set_stylebox("focus", kind, box(Color.TRANSPARENT, 6, ACCENT))
		result.set_color("caret_color", kind, INK)
		result.set_color("selection_color", kind, SELECTED)
		result.set_color("background_color", kind, PANEL)
		result.set_color("font_placeholder_color", kind, MUTED)
	result.set_color("line_number_color", "CodeEdit", MUTED)
	result.set_color("current_line_color", "CodeEdit", HOVER)
	result.set_color("executing_line_color", "CodeEdit", Color("d9f0e9"))
	result.set_color("code_folding_color", "CodeEdit", MUTED)
	result.set_color("default_color", "RichTextLabel", INK)
	result.set_color("selection_color", "RichTextLabel", SELECTED)
	result.set_color("font_shadow_color", "RichTextLabel", Color.TRANSPARENT)
	for kind in ["Tree", "ItemList"]:
		result.set_stylebox("panel", kind, box(PANEL, 6, LINE))
		result.set_stylebox("focus", kind, box(Color.TRANSPARENT, 6, ACCENT))
		result.set_stylebox("hovered", kind, box(HOVER, 3))
		result.set_stylebox("selected", kind, box(SELECTED, 3))
		result.set_stylebox("selected_focus", kind, box(SELECTED, 3, ACCENT))
		result.set_color("font_hovered_color", kind, INK)
		result.set_color("font_hovered_selected_color", kind, INK)
		result.set_color("guide_color", kind, LINE)
	result.set_constant("modulate_arrow", "OptionButton", 1)
	for direction in ["up", "down"]:
		for state in ["", "_hover", "_pressed"]:
			result.set_color(direction + state + "_icon_modulate", "SpinBox", MUTED)
		result.set_color(direction + "_disabled_icon_modulate", "SpinBox", Color("99a4b9"))
	for kind in ["HScrollBar", "VScrollBar"]:
		for role in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = CANVAS if role.begins_with("scroll") else Color("b7c2d3")
			if role == "grabber_highlight" or role == "grabber_pressed":
				style.bg_color = MUTED
			style.set_corner_radius_all(4)
			style.content_margin_left = 6
			style.content_margin_top = 6
			result.set_stylebox(role, kind, style)
	result.set_stylebox("panel", "TabContainer", box(PANEL, 8, LINE))
	result.set_stylebox("tab_selected", "TabBar", box(PANEL, 6, LINE))
	result.set_stylebox("tab_unselected", "TabBar", box(CANVAS, 6))
	result.set_stylebox("tab_hovered", "TabBar", box(HOVER, 6))
	result.set_color("font_selected_color", "TabBar", ACCENT)
	result.set_color("font_unselected_color", "TabBar", MUTED)
	result.set_color("font_hovered_color", "TabBar", INK)
	# TabContainer exposes its embedded tab styles under its own theme type.
	for style in ["tab_selected", "tab_unselected", "tab_hovered"]:
		result.set_stylebox(style, "TabContainer", result.get_stylebox(style, "TabBar"))
	for role in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
		result.set_color(role, "TabContainer", result.get_color(role, "TabBar"))
	result.set_stylebox("panel", "PopupMenu", box(PANEL, 8, LINE))
	result.set_stylebox("hover", "PopupMenu", box(SELECTED, 4))
	result.set_stylebox("panel", "AcceptDialog", box(PANEL, 10, LINE))
	var window_border := box(PANEL, 8, LINE)
	window_border.expand_margin_top = 32
	window_border.content_margin_top = 32
	window_border.shadow_color = Color(0.067, 0.11, 0.19, 0.15)
	window_border.shadow_size = 14
	result.set_stylebox("embedded_border", "Window", window_border)
	result.set_stylebox("embedded_unfocused_border", "Window", window_border)
	result.set_constant("title_height", "Window", 28)
	result.set_color("title_color", "Window", INK)
	result.set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	result.set_icon("close", "Window", load("res://assets/close.svg"))
	result.set_icon("close_pressed", "Window", load("res://assets/close.svg"))
	result.set_stylebox("selected", "Tree", box(SELECTED, 3))
	result.set_stylebox("selected_focus", "Tree", box(SELECTED, 3, ACCENT))
	result.set_stylebox("hovered", "Tree", box(HOVER, 3))
	result.set_stylebox("title_button_normal", "Tree", box(CANVAS, 0))
	result.set_stylebox("title_button_hover", "Tree", box(HOVER, 0))
	result.set_stylebox("title_button_pressed", "Tree", box(SELECTED, 0))
	result.set_color("title_button_color", "Tree", MUTED)
	for kind in ["HSeparator", "VSeparator"]:
		var separator := StyleBoxLine.new()
		separator.color = LINE
		separator.thickness = 1
		separator.vertical = kind == "VSeparator"
		result.set_stylebox("separator", kind, separator)
		result.set_constant("separation", kind, 8)
	return result

static func emphasize(button: Button, danger: bool = false) -> void:
	var color := FAILURE if danger else ACCENT
	button.add_theme_stylebox_override("normal", box(color))
	button.add_theme_stylebox_override("hover", box(color.darkened(0.04) if danger else color.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", box(color.darkened(0.12)))
	button.add_theme_stylebox_override("hover_pressed", box(color.darkened(0.12)))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)
