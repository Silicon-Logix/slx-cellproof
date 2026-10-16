# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends Control

const ClientScript = preload("res://core_client.gd")
const ViewScript = preload("res://workcell_view.gd")
const Palette = preload("res://slx_theme.gd")
const ProductDialogs = preload("res://product_dialogs.gd")
const InspectorScript = preload("res://cycle_inspector.gd")
const ProjectsScript = preload("res://project_controller.gd")
const UpdatesScript = preload("res://update_manager.gd")
const INK := Palette.INK
const MUTED := Palette.MUTED
const ACCENT := Palette.ACCENT
const SUCCESS := Palette.SUCCESS
const PANEL := Palette.PANEL
var navigation_buttons: Array[Button] = []

var core: Node
var cell_view: SubViewportContainer
var editor: CodeEdit
var pages: TabContainer
var pendant_pages: TabContainer
var status_label: Label
var time_label: Label
var tcp_label: Label
var event_log: RichTextLabel
var result_tree: Tree
var report_label: Label
var comparison_label: Label
var operation_label: Label
var monitor_label: Label
var joint_labels: Array[Label] = []
var point_select: OptionButton
var point_fields: Array[SpinBox] = []
var part_select: OptionButton
var fault_select: OptionButton
var report: Dictionary = {}
var state: Dictionary = {}
var points: Dictionary = {}
var pending_action := ""
var export_path := ""
var campaign_busy := false
var playback_rate := 1.0
var accumulator := 0.0
var monitor_connected := false
var monitor_poll := 0.0
var last_events := ""
var poll_accumulator := 0.0
var backend_ready := false
var error_dialog: AcceptDialog
var save_dialog: FileDialog
var screenshot_done := false
var recipe_dialog: FileDialog
var recipe_save_dialog: FileDialog
var recipe_save_path := ""
var source_label: Label
var measurement_label: Label
var product_dialogs: Node
var inspector: VBoxContainer
var simulation_toolbar: Control
var projects: Node
var project_caption: Label
var speed_field: SpinBox
var simulation_rate_select: OptionButton
var obstruction_toggle: CheckButton
var updates: Node
var guards_toggle: CheckButton
var markers_toggle: CheckButton

func _ready() -> void:
	# Keep engine dialogs and built-in controls in the product's English locale.
	TranslationServer.set_locale("en")
	_make_theme()
	projects = ProjectsScript.new()
	add_child(projects)
	updates = UpdatesScript.new()
	add_child(updates)
	product_dialogs = ProductDialogs.new()
	product_dialogs.attach(self)
	_build_layout()
	projects.setup()
	updates.attach(self)
	editor.text_changed.connect(_editor_changed)
	editor.text_set.connect(_editor_changed)
	core = ClientScript.new()
	add_child(core)
	core.response.connect(_response)
	core.failed.connect(_failed)
	core.start()

func _editor_changed() -> void:
	projects.mark_dirty()
	if not inspector.recording.is_empty() and not inspector.imported and not inspector.busy:
		inspector.refresh_badge()

func _make_theme() -> void:
	theme = Palette.create()

func _box(color: Color, radius: int = 6, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	return Palette.box(color, radius, border)

func _label(text: String, size_px: int = 15, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, action: Callable, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 38
	if accent:
		Palette.emphasize(b)
	b.pressed.connect(action)
	return b

func _margin(child: Control, padding: int = 16) -> MarginContainer:
	var m := MarginContainer.new()
	# Preserve expansion through wrappers, including scrollable pendant panels.
	m.size_flags_horizontal = child.size_flags_horizontal
	m.size_flags_vertical = child.size_flags_vertical
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, padding)
	m.add_child(child)
	return m

func _vbox(gap: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v

func _note(parent: Node, text: String, color: Color = MUTED) -> Label:
	var label := _label(text, 13, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = Palette.CANVAS
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var root := _vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(158, 40)
	header.add_child(logo)
	header.add_child(VSeparator.new())
	var title := _vbox(1)
	title.add_child(_label("CellProof", 27, Palette.ON_DARK))
	project_caption = _label("Untitled project", 11, Palette.DARK_MUTED)
	project_caption.custom_minimum_size.x = 200
	project_caption.clip_text = true
	project_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_child(project_caption)
	header.add_child(title)
	header.add_child(projects.make_menu(self))
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(space)
	header.add_child(_label("UR5e + CNC WORKCELL", 13, Palette.DARK_MUTED))
	source_label = _label("  NOMINAL SIMULATION  ", 12, Color("9be5cf"))
	header.add_child(source_label)
	var help := MenuButton.new()
	help.text = "Help"
	help.custom_minimum_size.y = 38
	for role in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		help.add_theme_color_override(role, Palette.ON_DARK)
	help.add_theme_stylebox_override("normal", _box(Palette.NAVY, 6, Color("35435a")))
	help.add_theme_stylebox_override("hover", _box(Color("283954"), 6, Color("35435a")))
	help.add_theme_stylebox_override("pressed", _box(Color("283954"), 6, Color("35435a")))
	help.add_theme_stylebox_override("hover_pressed", _box(Color("283954"), 6, Color("35435a")))
	var help_menu := help.get_popup()
	for item in ["User guide  ·  F1", "SLX language and API", "License", "Third-party notices", "About CellProof  ·  F12", "Check for updates…"]:
		help_menu.add_item(item)
	help_menu.id_pressed.connect(func(id: int):
		if id == 4:
			product_dialogs.show_about()
		elif id == 5:
			updates.check()
		else:
			product_dialogs.show_document(["guide", "api", "license", "notices"][id]))
	header.add_child(help)
	header.add_child(_button("About", product_dialogs.show_about))
	header.add_child(_button("Custom engineering", func(): pages.current_tab = 3))
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _box(Palette.NAVY, 0))
	header_panel.add_child(_margin(header, 10))
	root.add_child(header_panel)
	root.add_child(HSeparator.new())
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	part_select = OptionButton.new()
	for variant in ["Part A · Ø40", "Part B · Ø50", "Part C · Ø60 / incompatible"]:
		part_select.add_item(variant)
	part_select.item_selected.connect(func(index: int): core.request("configuration.set", {"part": ["A", "B", "C"][index]}))
	toolbar.add_child(part_select)
	toolbar.add_child(_button("Validate program", func(): _sync_then("validate")))
	toolbar.add_child(_button("▶ Run", func(): _sync_then("run"), true))
	toolbar.add_child(_button("Ⅱ Pause", func(): core.request("pause")))
	toolbar.add_child(_button("Resume", func(): core.request("resume")))
	var stop := _button("■ STOP", func(): core.request("stop"))
	Palette.emphasize(stop, true)
	toolbar.add_child(stop)
	var toolbar_space := Control.new()
	toolbar_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(toolbar_space)
	toolbar.add_child(_button("Verify change", func(): _sync_then("campaign.run"), true))
	simulation_toolbar = _margin(toolbar, 12)
	root.add_child(simulation_toolbar)
	pages = TabContainer.new()
	pages.tabs_visible = false
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sidebar := _vbox(12)
	sidebar.custom_minimum_size.x = 174
	sidebar.add_child(_label("WORKSPACE", 11, MUTED))
	var navigation := ["01  Programming", "02  Cycle Inspector", "03  Verify change", "04  Connections", "05  SLX services"]
	for index in range(navigation.size()):
		var target: int = [0, 4, 1, 2, 3][index]
		var nav_button := _button(navigation[index], func(): pages.current_tab = target)
		nav_button.set_meta("page", target)
		nav_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		navigation_buttons.append(nav_button)
		sidebar.add_child(nav_button)
	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_label("INCLUDED IN THE DEMO", 10, SUCCESS))
	_note(sidebar, "Nominal UR5e\nSLX CNC and gripper\nPTP / LIN programs\nCycle replay and IO\n8 verification scenarios")
	var side_space := Control.new()
	side_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(side_space)
	_note(sidebar, "Demonstration models.\nInstallation validation requires calibrated data and dedicated commissioning.")
	sidebar.add_child(_label("Silicon LogiX  /  v" + str(ProjectSettings.get_setting("application/config/version")), 11, MUTED))
	var sidebar_panel := PanelContainer.new()
	sidebar_panel.add_theme_stylebox_override("panel", _box(PANEL, 8, Palette.LINE))
	sidebar_panel.add_child(_margin(sidebar, 0))
	body.add_child(sidebar_panel)
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(pages)
	root.add_child(_margin(body, 10))
	_build_program_page()
	_build_verification_page()
	_build_connections_page()
	_build_services_page()
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.name = "Cycle Inspector"
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.add_child(inspector_scroll)
	inspector = InspectorScript.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(inspector)
	inspector.attach(self)
	pages.tab_changed.connect(_select_navigation)
	_select_navigation(0)
	var footer := HBoxContainer.new()
	status_label = _label("● Starting C++ core…", 13, SUCCESS)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status_label)
	time_label = _label("Simulated time  0.0 s", 13, MUTED)
	footer.add_child(time_label)
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", _box(PANEL, 0, Palette.LINE))
	footer_panel.add_child(_margin(footer, 0))
	root.add_child(footer_panel)
	error_dialog = AcceptDialog.new()
	error_dialog.title = "SLX CellProof · diagnostics"
	error_dialog.min_size = Vector2i(640, 160)
	add_child(error_dialog)
	save_dialog = FileDialog.new()
	save_dialog.title = "Export verification report"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.filters = PackedStringArray(["*.html ; Readable report", "*.json ; Structured evidence"])
	save_dialog.file_selected.connect(_save_report)
	add_child(save_dialog)
	recipe_dialog = FileDialog.new()
	recipe_dialog.title = "Open CellProof recipe"
	recipe_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	recipe_dialog.access = FileDialog.ACCESS_FILESYSTEM
	recipe_dialog.filters = PackedStringArray(["*.json ; SLX CellProof recipe"])
	recipe_dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 50000:
			_failed("recipe.import", "FILE_LIMIT", "Recipe unreadable or larger than 50 KB")
			return
		var value = JSON.parse_string(file.get_as_text())
		if value is Dictionary:
			projects.before_replacing(func(): core.request("recipe.import", {"recipe": value}))
		else:
			_failed("recipe.import", "INVALID_JSON", "The file does not contain a valid JSON recipe"))
	add_child(recipe_dialog)
	recipe_save_dialog = FileDialog.new()
	recipe_save_dialog.title = "Save CellProof recipe"
	recipe_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	recipe_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	recipe_save_dialog.filters = PackedStringArray(["*.json ; SLX CellProof recipe"])
	recipe_save_dialog.file_selected.connect(func(path: String): recipe_save_path = path; _sync_then("recipe.export"))
	add_child(recipe_save_dialog)

func _select_navigation(index: int) -> void:
	simulation_toolbar.visible = index != 4
	for item in range(navigation_buttons.size()):
		var button := navigation_buttons[item]
		var selected: bool = button.get_meta("page", item) == index
		button.add_theme_stylebox_override("normal", _box(Palette.SELECTED if selected else PANEL, 6))
		button.add_theme_stylebox_override("hover", _box(Palette.SELECTED if selected else Palette.HOVER, 6))
		button.add_theme_stylebox_override("pressed", _box(Palette.SELECTED, 6))
		button.add_theme_stylebox_override("hover_pressed", _box(Palette.SELECTED, 6))
		for role in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(role, ACCENT if selected else MUTED)
	if index == 4 and backend_ready:
		core.request("inspector.info")
	if index == 4:
		source_label.text = "RECORDED SIMULATION"
	elif not monitor_connected:
		source_label.text = "NOMINAL SIMULATION"

func _build_program_page() -> void:
	var page := HSplitContainer.new()
	page.name = "Programming"
	page.split_offset = 0
	pages.add_child(page)
	var visual := _vbox(8)
	visual.custom_minimum_size.x = 480
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var caption := HBoxContainer.new()
	caption.add_child(_label("Demonstration workcell", 21))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_child(spacer)
	var guards := CheckButton.new()
	guards_toggle = guards
	guards.text = "Show guards"
	guards.toggled.connect(func(value: bool): cell_view.set_guards(value))
	caption.add_child(guards)
	visual.add_child(caption)
	cell_view = ViewScript.new()
	cell_view.custom_minimum_size.y = 360
	visual.add_child(cell_view)
	var view_tools := HBoxContainer.new()
	var markers := CheckButton.new()
	markers_toggle = markers
	markers.text = "Taught points"
	markers.toggled.connect(func(value: bool): cell_view.markers.visible = value)
	view_tools.add_child(markers)
	view_tools.add_child(_button("Reset view", func(): cell_view.angle = -2.3; cell_view.elevation = 0.46; cell_view.distance = 4.8; cell_view._update_camera()))
	var playback := OptionButton.new()
	simulation_rate_select = playback
	for value in ["Simulation 1×", "Simulation 2×", "Simulation 5×"]:
		playback.add_item(value)
	playback.item_selected.connect(func(index: int): playback_rate = [1.0, 2.0, 5.0][index])
	view_tools.add_child(playback)
	visual.add_child(view_tools)
	tcp_label = _label("TCP · cell_world · m / rad", 13, MUTED)
	visual.add_child(tcp_label)
	measurement_label = _note(visual, "DEMO DATA · synthetic metrology, awaiting a cycle", Palette.ATTENTION)
	_note(visual, "Drag to orbit · scroll to zoom. Guards hidden in the view only. Geometry checks use sampled proxies.")
	event_log = RichTextLabel.new()
	event_log.custom_minimum_size.y = 120
	event_log.bbcode_enabled = true
	event_log.scroll_following = true
	event_log.add_theme_font_size_override("normal_font_size", 13)
	visual.add_child(event_log)
	page.add_child(_margin(visual, 8))
	pendant_pages = TabContainer.new()
	pendant_pages.custom_minimum_size.x = 410
	pendant_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(pendant_pages)
	var program_panel := _vbox(10)
	program_panel.name = "SLX editor"
	pendant_pages.add_child(program_panel)
	program_panel.add_child(_label("Workcell recipe", 19))
	_note(program_panel, "PTP / LIN · GRIP · WAIT with timeout · CNC · MEASURE")
	editor = CodeEdit.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.gutters_draw_line_numbers = true
	editor.gutters_draw_executing_lines = true
	editor.highlight_current_line = true
	editor.add_theme_font_size_override("font_size", 14)
	var code_font := SystemFont.new()
	code_font.font_names = PackedStringArray(["Cascadia Code", "Consolas", "DejaVu Sans Mono"])
	editor.add_theme_font_override("font", code_font)
	var syntax := CodeHighlighter.new()
	syntax.number_color = Palette.ATTENTION
	syntax.symbol_color = MUTED
	for word in ["PTP", "LIN", "GRIP", "WAIT", "CNC", "MEASURE", "TIMEOUT", "SPEED"]:
		syntax.add_keyword_color(word, ACCENT)
	for word in ["OPEN", "CLOSE", "DOOR", "CLAMP", "UNCLAMP", "CYCLE"]:
		syntax.add_keyword_color(word, Palette.ATTENTION)
	syntax.add_color_region("#", "", MUTED, true)
	editor.syntax_highlighter = syntax
	program_panel.add_child(editor)
	var actions := HBoxContainer.new()
	actions.add_child(_button("Open…", func(): recipe_dialog.popup_centered_ratio(0.65)))
	actions.add_child(_button("Save…", func(): recipe_save_dialog.current_file = "CellProof-recipe.json"; recipe_save_dialog.popup_centered_ratio(0.65)))
	actions.add_child(_button("Reset program", func(): core.request("program.reset")))
	actions.add_child(_button("Baseline", func(): _sync_then("baseline.save")))
	program_panel.add_child(actions)
	_note(program_panel, "Program reset preserves the pose. Reset simulation explicitly restores the initial workcell state.")
	_build_pendant()
	_build_points()

func _build_pendant() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Pendant"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pendant_pages.add_child(scroll)
	var panel := _vbox(10)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_margin(panel, 12))
	panel.add_child(_label("Teach pendant", 20))
	_note(panel, "Included in the demo · simulator jog\nBase: cell_world · TCP: PG-60 gripper")
	var speed := SpinBox.new()
	speed_field = speed
	speed.min_value = 0.05
	speed.max_value = 0.5
	speed.step = 0.05
	speed.value = 0.35
	speed.suffix = "rad/s nominal"
	speed.value_changed.connect(func(value: float): core.request("configuration.set", {"speed": value}))
	panel.add_child(speed)
	panel.add_child(_button("Step · one instruction", func():
		if state.get("instruction_count", 0) == 0:
			_sync_then("step")
		else:
			core.request("step")))
	for axis in range(6):
		var row := HBoxContainer.new()
		var index := axis
		var label := _label("J%d  —" % (axis + 1), 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		joint_labels.append(label)
		row.add_child(label)
		row.add_child(_button("− 1°", func(): core.request("jog", {"axis": index, "delta_rad": -deg_to_rad(1)})))
		row.add_child(_button("+ 1°", func(): core.request("jog", {"axis": index, "delta_rad": deg_to_rad(1)})))
		panel.add_child(row)
	panel.add_child(HSeparator.new())
	panel.add_child(_label("Jog TCP · cell_world", 16))
	for axis in range(3):
		var row := HBoxContainer.new()
		var index := axis
		row.add_child(_label(["X", "Y", "Z"][axis], 14))
		for sign_value in [-1.0, 1.0]:
			var direction: float = sign_value
			row.add_child(_button("− 5 mm" if direction < 0 else "+ 5 mm", func():
				var delta := [0.0, 0.0, 0.0]
				delta[index] = 0.005 * direction
				core.request("jog.tcp", {"delta_m": delta})))
		panel.add_child(row)
	panel.add_child(HSeparator.new())
	panel.add_child(_label("Fault injection", 16))
	fault_select = OptionButton.new()
	for title in ["No fault", "Part absent", "Door blocked", "Machine permission missing", "Sensor delayed", "Connection lost"]:
		fault_select.add_item(title)
	fault_select.item_selected.connect(func(index: int): core.request("fault.set", {"scenario": ["none", "piece_absent", "door_blocked", "machine_permission_missing", "sensor_delayed", "link_loss"][index]}))
	panel.add_child(fault_select)
	panel.add_child(_button("Clear simulated faults", func(): core.request("recover")))
	panel.add_child(_button("Reset simulation", func(): core.request("simulation.reset")))
	_note(panel, "Recovery preserves the pose and part, then requires Resume. STOP controls the simulation; use the controller controls for a physical robot.")

func _build_points() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Points"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pendant_pages.add_child(scroll)
	var panel := _vbox(12)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	panel.add_child(_label("Taught points", 20))
	point_select = OptionButton.new()
	point_select.item_selected.connect(func(_index: int): _load_point())
	panel.add_child(point_select)
	for axis in ["X", "Y", "Z"]:
		var row := HBoxContainer.new()
		row.add_child(_label(axis + "  / mm", 14))
		var value := SpinBox.new()
		value.min_value = -800
		value.max_value = 1800
		value.step = 0.1
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value)
		point_fields.append(value)
		panel.add_child(row)
	panel.add_child(_button("Save edited pose", _update_point, true))
	_note(panel, "The selected point orientation is preserved. The core performs IK and geometry checks.")
	panel.add_child(HSeparator.new())
	var name_field := LineEdit.new()
	name_field.placeholder_text = "New point name: e.g. inspection_1"
	panel.add_child(name_field)
	panel.add_child(_button("Teach current pose", func(): core.request("point.teach", {"name": name_field.text.strip_edges()})))
	panel.add_child(HSeparator.new())
	var obstruction := CheckButton.new()
	obstruction_toggle = obstruction
	obstruction.text = "Add test fixture"
	obstruction.toggled.connect(func(value: bool): core.request("configuration.set", {"obstruction": {"center_m": [0.54, 0.0, 1.2], "size_m": [0.10, 0.20, 0.40]} if value else null}))
	panel.add_child(obstruction)
	_note(panel, "The orange proxy obstructs CNC access to test geometry rejection after a change.")

func _build_verification_page() -> void:
	var page := _vbox(16)
	page.name = "Verify change"
	pages.add_child(_margin(page, 22))
	page.add_child(_label("Verify change", 30))
	_note(page, "Run a campaign on the current configuration and compare nominal cycles against the previous baseline.")
	var actions := HBoxContainer.new()
	actions.add_child(_button("Run all 8 tests", func(): _sync_then("campaign.run"), true))
	actions.add_child(_button("Save current baseline", func(): _sync_then("baseline.save")))
	actions.add_child(_button("Export report…", func(): save_dialog.current_file = "CellProof-verification.html"; save_dialog.popup_centered_ratio(0.65)))
	page.add_child(actions)
	report_label = _label("No campaign run yet", 22, SUCCESS)
	page.add_child(report_label)
	result_tree = Tree.new()
	result_tree.columns = 5
	result_tree.hide_root = true
	result_tree.column_titles_visible = true
	for index in range(5):
		result_tree.set_column_title(index, ["Scenario", "Part", "Result", "Diagnostics", "Recovery"][index])
		result_tree.set_column_expand_ratio(index, [4, 1, 1, 4, 2][index])
	result_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_tree.custom_minimum_size.y = 300
	page.add_child(result_tree)
	comparison_label = _label("Comparison: save a baseline or complete the first campaign.", 15, MUTED)
	comparison_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(comparison_label)
	_note(page, "Tests query the C++ core and verify actual model outcomes. Faults must be detected and recovery must complete the cycle. Simulated time and host processing time are reported separately.")
	_note(page, "Geometry coverage: simplified proxies and discrete sampling. Results do not certify full mesh collision clearance or installation safety.", Palette.ATTENTION)

func _build_connections_page() -> void:
	var page := _vbox(16)
	page.name = "Connections"
	pages.add_child(_margin(page, 22))
	page.add_child(_label("Controller connections", 30))
	_note(page, "The monitor receives controller telemetry over RTDE v2. Physical motion commands are unavailable in this demo.")
	var kind := OptionButton.new()
	kind.add_item("URSim · simulated controller")
	kind.add_item("UR5e · physical robot monitor")
	page.add_child(kind)
	var ip := LineEdit.new()
	ip.placeholder_text = "Controller IPv4 address, configure explicitly"
	page.add_child(ip)
	var actions := HBoxContainer.new()
	actions.add_child(_button("Connect read only", func(): core.request("monitor.connect", {"kind": "ursim" if kind.selected == 0 else "ur5e", "ip": ip.text.strip_edges()}), true))
	actions.add_child(_button("Disconnect", func(): core.request("monitor.disconnect")))
	page.add_child(actions)
	monitor_label = _label("Disconnected · recorded data is never presented as live", 17, MUTED)
	monitor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(monitor_label)
	_note(page, "The 3D view follows received joints. Workcell placement and TCP remain nominal until calibrated for the installation. Stale data and connection loss are flagged.")
	page.add_child(HSeparator.new())
	page.add_child(_label("Assisted motion evaluation", 22))
	_note(page, "Custom engineering · requires installation-specific configuration, calibration, IO mapping and commissioning. The physical motion module is excluded from the public demo.")
	page.add_child(_button("Prepare installation requirements", _contact))
	page.add_child(HSeparator.new())
	_note(page, "RTDE monitoring verified against URSim e-Series 5.23.0 and a protocol test server. Physical UR5e connectivity requires installation testing. Demo campaigns produce simulated evidence.", Palette.ATTENTION)

func _build_services_page() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "SLX services"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.add_child(scroll)
	var page := _vbox(18)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_margin(page, 24))
	page.add_child(_label("From this demo to your workcell", 30))
	_note(page, "CellProof demonstrates the SLX approach to change verification and sequence testing. Custom engineering starts from your installation requirements.")
	_note(page, "AVAILABLE NOW · Cycle Inspector: synchronized 3D replay, sampled IO, baseline comparison, bookmarks and local JSON / CSV export.", SUCCESS)
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/advanced-services.json"))
	var services: Array = catalogue.get("services", [])
	for service in services:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box(PANEL, 8, Palette.LINE))
		var content := _vbox(8)
		content.add_child(_label("ON REQUEST · SCOPED ENGINEERING", 11, SUCCESS))
		content.add_child(_label(service.title, 21))
		_note(content, service.summary)
		_note(content, "Requires: " + service.requirements)
		_note(content, "Deliverable: " + service.deliverable)
		var links := HBoxContainer.new()
		for reference in service.references:
			var url: String = reference.url
			links.add_child(_button(reference.label, func(): OS.shell_open(url)))
		var topic: String = service.title
		links.add_child(_button("Request this integration", func(): _contact(topic)))
		content.add_child(links)
		card.add_child(_margin(content, 16))
		page.add_child(card)
	page.add_child(_button("Describe your robot, machine and challenge", _contact, true))
	_note(page, "Prepare a brief to copy. Programs, files and installation data are never transmitted automatically.")

func _contact(topic: String = "") -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Silicon LogiX integration enquiry"
	dialog.min_size = Vector2i(700, 430)
	dialog.ok_button_text = "Close"
	var fields := _vbox(12)
	var inputs: Array[LineEdit] = []
	for title in ["Robot / model / controller", "CNC machine or PLC", "Process and tooling", "Change or problem to solve"]:
		fields.add_child(_label(title, 14))
		var input := LineEdit.new()
		fields.add_child(input)
		inputs.append(input)
	inputs[3].text = topic
	fields.add_child(_button("Copy brief to clipboard", func():
		var text := "SLX CellProof project enquiry\n"
		for index in range(inputs.size()):
			text += ["Robot: ", "Machine: ", "Process: ", "Challenge: "][index] + inputs[index].text + "\n"
		DisplayServer.clipboard_set(text), true))
	_note(fields, "Only the text you enter is copied. Send it to your Silicon LogiX contact through your preferred channel.")
	dialog.add_child(_margin(fields, 20))
	add_child(dialog)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.popup_centered()

func _sync_then(action: String) -> void:
	if not backend_ready or campaign_busy or pending_action != "" or inspector.busy or projects.busy:
		return
	pending_action = action
	core.request("program.set", {"text": editor.text})

func _response(operation: String, result: Dictionary) -> void:
	if operation == "open":
		backend_ready = true
		product_dialogs.core_version = result.get("version", "Unknown")
		editor.text = result.program
		_set_points(result.points)
		_apply_state(result.state)
		projects.core_opened()
	elif operation == "session.renew":
		status_label.text = "● Demo session renewed · workspace preserved"
	elif operation in ["project.commit", "project.new"]:
		editor.text = result.program
		_set_points(result.points)
		_apply_state(result.state)
		report = {}
		result_tree.clear()
		report_label.text = "Run Verify change to generate current evidence"
		comparison_label.text = "Baseline restored" if result.state.baseline_available else "Save a baseline to compare recipe changes"
		inspector.clear_recording()
	elif operation == "program.set":
		var action := pending_action
		pending_action = ""
		if action != "":
			if action == "campaign.run":
				campaign_busy = true
				report_label.text = "Campaign running in the core…"
				pages.current_tab = 1
			core.request(action, inspector.capture_parameters() if action == "inspector.capture" else {})
	elif operation.begins_with("inspector."):
		inspector.handle_response(operation, result)
	elif operation == "validate":
		status_label.text = "● Program valid · %d geometry samples" % result.geometry_samples
	elif operation == "baseline.save":
		comparison_label.text = "Baseline saved · " + str(result.configuration_sha256).left(16)
		status_label.text = "● Current baseline saved"
	elif operation == "campaign.run":
		campaign_busy = false
		report = result
		_render_report()
		status_label.text = "● Campaign complete · %d / %d tests" % [result.passed, result.total]
	elif operation == "report.get":
		if export_path != "":
			var file := FileAccess.open(export_path, FileAccess.WRITE)
			if file:
				file.store_string(result.html if result.has("html") else JSON.stringify(result, "  "))
				status_label.text = "● Report exported: " + export_path.get_file()
			else:
				_failed(operation, "WRITE_ERROR", "Cannot write the report to the selected path")
			export_path = ""
	elif operation == "point.teach" or operation == "point.update":
		_set_points(result.points)
		status_label.text = "● Point saved: " + result.name
	elif operation == "recipe.import":
		editor.text = result.program
		_set_points(result.points)
		_apply_state(result.state)
	elif operation == "recipe.export":
		if recipe_save_path != "":
			var file := FileAccess.open(recipe_save_path, FileAccess.WRITE)
			if file:
				file.store_string(JSON.stringify(result, "  "))
				status_label.text = "● Recipe saved locally"
			else:
				_failed(operation, "WRITE_ERROR", "Cannot save the recipe")
			recipe_save_path = ""
	elif operation.begins_with("monitor."):
		monitor_connected = result.get("connected", false)
		if monitor_connected:
			var source: String = result.get("source", "controller")
			source_label.text = "MONITOR " + ("URSim" if source == "ursim_controller" else "UR5e") + " · READ ONLY"
			var reception := "STALE DATA" if result.get("stale", false) else ("receiving telemetry" if result.get("has_sample", false) else "awaiting first sample")
			monitor_label.text = source + " · READ ONLY · " + reception
			if result.get("has_sample", false):
				cell_view.apply_joints(result.joints_rad)
				for index in range(6):
					joint_labels[index].text = "J%d    %7.2f°" % [index + 1, rad_to_deg(result.joints_rad[index])]
				var tcp: Array = result.tcp_base_pose_m_rad
				tcp_label.text = "TCP · UR base · controller reading    X %.1f   Y %.1f   Z %.1f mm" % [tcp[0] * 1000, tcp[1] * 1000, tcp[2] * 1000]
				time_label.text = "Controller timestamp  %.2f s" % result.controller_time_s
				monitor_label.text += "\nController timestamp: %.3f s · sample age: %.2f s" % [result.controller_time_s, result.sample_age_s]
			status_label.text = "● Monitor " + source + " · motion disabled"
		else:
			source_label.text = "NOMINAL SIMULATION"
			source_label.add_theme_color_override("font_color", Color("9be5cf"))
			monitor_label.text = "Disconnected · " + str(result.get("error", "no motion commands sent"))
	elif result.has("joints_rad"):
		_apply_state(result)
	if operation in ["configuration.set", "point.update", "point.teach", "baseline.save", "campaign.run", "recipe.import", "program.set"] and not inspector.recording.is_empty() and not inspector.busy and not inspector.imported:
		core.request("inspector.info")
	if pages.current_tab == 4:
		_inspector_context()
	projects.handle_response(operation, result)
	updates.handle_response(operation, result)

func _inspector_context() -> void:
	source_label.text = "RECORDED SIMULATION"
	status_label.text = "● Cycle Inspector · recorded simulation · open cell: " + str(state.get("status", "idle"))
	status_label.add_theme_color_override("font_color", MUTED)
	time_label.text = "Replay  %.1f s" % inspector.play_time

func _apply_state(value: Dictionary) -> void:
	state = value
	var configuration: Dictionary = value.get("configuration", {})
	speed_field.set_value_no_signal(configuration.get("speed", 0.35))
	obstruction_toggle.set_pressed_no_signal(configuration.get("obstruction") != null)
	var measurement = value.get("measurement")
	if measurement is Dictionary:
		measurement_label.text = "DEMO DATA · Ø%.3f mm · nominal %.2f mm · tolerance ±%.2f mm" % [measurement.value_mm, measurement.nominal_mm, measurement.tolerance_mm]
	else:
		measurement_label.text = "DEMO DATA · synthetic metrology, awaiting a cycle"
	part_select.select(["A", "B", "C"].find(value.get("part_variant", "A")))
	fault_select.select(["none", "piece_absent", "door_blocked", "machine_permission_missing", "sensor_delayed", "link_loss"].find(value.get("injected_fault", "none")))
	if not monitor_connected:
		cell_view.apply_state(value)
	var q: Array = value.get("joints_rad", [])
	if not monitor_connected:
		for index in range(mini(6, q.size())):
			joint_labels[index].text = "J%d    %7.2f°" % [index + 1, rad_to_deg(q[index])]
	var xyz: Array = value.tcp.tcp_xyz_m
	if not monitor_connected:
		tcp_label.text = "TCP · cell_world    X %.1f   Y %.1f   Z %.1f mm" % [xyz[0] * 1000, xyz[1] * 1000, xyz[2] * 1000]
		time_label.text = "Simulated time  %.1f s" % value.simulated_time_s
	if not campaign_busy and not monitor_connected:
		var titles := {"idle": "Ready", "running": "Running", "paused": "Paused", "stopped": "Stopped", "completed": "Cycle complete", "fault": "Fault detected"}
		status_label.text = "● " + titles.get(value.status, value.status) + " · SIMULATION"
		if value.get("error_code", "") != "":
			status_label.text += " · " + value.error_code
		status_label.add_theme_color_override("font_color", Palette.FAILURE if value.status == "fault" else SUCCESS)
	var events: Array = value.get("events", [])
	var signature := JSON.stringify(events)
	if signature != last_events:
		last_events = signature
		event_log.clear()
		for item in events.slice(maxi(0, events.size() - 8)):
			event_log.add_text("%6.1f s  ·  %s  %s\n" % [item.time_s, item.code, item.message])
	for line in range(editor.get_line_count()):
		editor.set_line_as_executing(line, line + 1 == int(value.get("line", 0)))

func _set_points(value: Dictionary) -> void:
	points = value
	point_select.clear()
	for name in points:
		point_select.add_item(name)
	cell_view.set_points(points)
	_load_point()

func _load_point() -> void:
	if point_select.item_count == 0:
		return
	var name := point_select.get_item_text(point_select.selected)
	var xyz: Array = points[name].tcp_xyz_m
	for index in range(3):
		point_fields[index].value = xyz[index] * 1000

func _update_point() -> void:
	if point_select.item_count == 0:
		return
	var name := point_select.get_item_text(point_select.selected)
	var pose: Dictionary = points[name].duplicate(true)
	pose.tcp_xyz_m = [point_fields[0].value / 1000, point_fields[1].value / 1000, point_fields[2].value / 1000]
	core.request("point.update", {"name": name, "pose": pose})

func _render_report() -> void:
	report_label.text = "%d / %d tests passed · simulated evidence" % [report.passed, report.total]
	result_tree.clear()
	var root := result_tree.create_item()
	for item in report.cases:
		var row := result_tree.create_item(root)
		var names := {"none": "Nominal cycle", "piece_absent": "Part absent", "door_blocked": "Door blocked", "machine_permission_missing": "Permission missing", "sensor_delayed": "Sensor delayed", "link_loss": "Connection lost"}
		row.set_text(0, "Incompatible part rejection" if item.part == "C" else names.get(item.fault, item.fault))
		row.set_text(1, item.part)
		row.set_text(2, "PASS" if item.passed else "FAIL")
		row.set_custom_color(2, SUCCESS if item.passed else Palette.FAILURE)
		row.set_text(3, item.get("code", ""))
		row.set_text(4, "Verified" if item.get("recovery_verified", false) else "—")
		row.set_tooltip_text(3, item.get("diagnostic", ""))
	var comparison = report.get("comparison")
	if comparison is Dictionary:
		var text := "Comparison against baseline rerun by the backend:\n"
		for item in comparison.differences:
			text += "Part %s · simulated time Δ %+.2f s · before %s / after %s\n" % [item.part, item.simulated_duration_delta_s, "PASS" if item.before_passed else "FAIL", "PASS" if item.after_passed else "FAIL"]
		comparison_label.text = text
	else:
		comparison_label.text = "First campaign: configuration saved as the baseline for the next comparison."

func _save_report(path: String) -> void:
	if report.is_empty():
		_failed("report.get", "NO_REPORT", "Run Verify change first")
		return
	export_path = path
	core.request("report.get", {"format": "html" if path.get_extension().to_lower() == "html" else "json"})

func _failed(operation: String, code: String, message: String) -> void:
	projects.operation_failed(operation, message)
	updates.operation_failed(operation, message)
	if inspector.busy and (operation.begins_with("inspector.") or operation in ["program.set", "transport", "startup"]):
		inspector.fail_load(message)
	if operation == "transport" or operation == "startup":
		backend_ready = false
		source_label.text = "CORE UNAVAILABLE"
		source_label.add_theme_color_override("font_color", Color("ffbac0"))
	pending_action = ""
	if operation == "campaign.run":
		campaign_busy = false
	status_label.text = "● " + code + " · " + message
	status_label.add_theme_color_override("font_color", Palette.FAILURE)
	if operation not in ["tick", "state", "transport"]:
		error_dialog.dialog_text = message + "\n\nCode: " + code
		error_dialog.popup_centered()
	push_warning(operation + ": " + code + " · " + message)

func _process(delta: float) -> void:
	if not backend_ready or campaign_busy or inspector.busy:
		return
	accumulator += delta
	if state.get("status", "") == "running" and accumulator >= 0.05 and not core.tick_pending:
		core.request("tick", {"dt_s": minf(0.25, accumulator * playback_rate)})
		accumulator = 0.0
	poll_accumulator += delta
	if poll_accumulator >= 0.5 and state.get("status", "") != "running" and core.pending.is_empty():
		core.request("state")
		poll_accumulator = 0.0
	monitor_poll += delta
	if monitor_connected and monitor_poll >= 0.05 and core.pending.is_empty():
		core.request("monitor.read")
		monitor_poll = 0.0
	if "--smoke" in OS.get_cmdline_user_args() and not screenshot_done and Time.get_ticks_msec() > 3500:
		screenshot_done = true
		print("SLX_GUI_SMOKE_OK: backend session open; articulated workcell loaded")
		get_tree().quit()
	if "--capture" in OS.get_cmdline_user_args() and not screenshot_done and Time.get_ticks_msec() > 4500:
		screenshot_done = true
		_capture.call_deferred()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F1:
		product_dialogs.show_document("guide")
	elif event.keycode == KEY_F12:
		product_dialogs.show_about()
	elif not product_dialogs.has_open_dialog() and not projects.has_open_dialog() and not projects.busy and not error_dialog.visible and not recipe_dialog.visible and not recipe_save_dialog.visible and not save_dialog.visible:
		if event.ctrl_pressed and event.keycode == KEY_O:
			projects.before_replacing(func(): projects.open_dialog.popup_centered_ratio(0.72))
		elif event.ctrl_pressed and event.keycode == KEY_S:
			projects.save_project(event.shift_pressed)
		elif event.ctrl_pressed and event.keycode == KEY_N:
			projects.before_replacing(projects.new_project)
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/gui-preview.png"))
	print("SLX_GUI_CAPTURE_OK")
	get_tree().quit()
