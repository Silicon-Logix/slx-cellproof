# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends Control

signal seek_requested(time_s: float)
const LANES := ["Motion", "CNC handling", "Machining", "Gripper", "IO wait", "Measurement"]
const COLORS := [Color("5354e8"), Color("177a9c"), Color("087762"), Color("ac6820"), Color("b14f85"), Color("68758d")]
const SIGNALS := ["door_open", "grip_confirmed", "machine_ready"]
var intervals: Array = []
var frames: Array = []
var baseline_intervals: Array = []
var signal_spans: Dictionary = {}
var baseline_signal_spans: Dictionary = {}
var bookmarks: Array = []
var events: Array = []
var duration := 1.0
var playhead := 0.0

func _ready() -> void:
	custom_minimum_size.y = 160
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Click or drag to seek. Upper solid bars: current; lower pale bars: baseline. IO holds its last sample after a run ends."

func set_samples(current: Array, baseline: Array) -> void:
	frames = current
	signal_spans = _spans(current)
	baseline_signal_spans = _spans(baseline)
	queue_redraw()

func _spans(samples: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in SIGNALS:
		result[key] = []
		var start := -1.0
		for sample in samples:
			if sample.io.get(key, false) and start < 0:
				start = sample.time_s
			elif not sample.io.get(key, false) and start >= 0:
				result[key].append(Vector2(start, sample.time_s))
				start = -1
		if start >= 0:
			result[key].append(Vector2(start, duration))
	return result

func _x(time_s: float) -> float:
	return 116.0 + time_s / maxf(duration, 0.1) * maxf(size.x - 126, 1)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("f3f5f9"))
	var font := ThemeDB.fallback_font
	for i in range(LANES.size()):
		var y := 7.0 + i * 14
		draw_string(font, Vector2(7, y + 11), LANES[i], HORIZONTAL_ALIGNMENT_LEFT, 106, 11, Color("68758d"))
		draw_rect(Rect2(116, y, maxf(size.x - 126, 1), 12), Color("e9edf4"))
	for interval in intervals:
		var lane: int = LANES.find(interval.phase)
		if lane >= 0:
			draw_rect(Rect2(_x(interval.start_s), 7 + lane * 14, maxf(_x(interval.end_s) - _x(interval.start_s), 2), 7 if not baseline_intervals.is_empty() else 12), COLORS[lane])
	for interval in baseline_intervals:
		var lane: int = LANES.find(interval.phase)
		if lane >= 0:
			draw_rect(Rect2(_x(interval.start_s), 15 + lane * 14, maxf(_x(interval.end_s) - _x(interval.start_s), 2), 4), Color(COLORS[lane], 0.35))
	for i in range(SIGNALS.size()):
		var y := 95.0 + i * 14
		draw_string(font, Vector2(7, y + 10), SIGNALS[i], HORIZONTAL_ALIGNMENT_LEFT, 107, 10, Color("68758d"))
		draw_rect(Rect2(116, y, maxf(size.x - 126, 1), 10), Color("e9edf4"))
		for span in signal_spans.get(SIGNALS[i], []):
			draw_rect(Rect2(_x(span.x), y, maxf(_x(span.y) - _x(span.x), 1), 5 if not baseline_intervals.is_empty() else 10), Color("65bca3"))
		for span in baseline_signal_spans.get(SIGNALS[i], []):
			draw_rect(Rect2(_x(span.x), y + 6, maxf(_x(span.y) - _x(span.x), 1), 4), Color("bddfd5"))
	for event in events:
		if event.code not in ["STARTED", "STEP_COMPLETED", "COMPLETED"]:
			draw_line(Vector2(_x(event.time_s), 4), Vector2(_x(event.time_s), 137), Color("ba344d"), 2)
	for mark in bookmarks:
		draw_circle(Vector2(_x(mark.time_s), 140), 4, Color("ac6820"))
	for i in range(5):
		var t := duration * i / 4.0
		draw_string(font, Vector2(clampf(_x(t) - 12, 116, size.x - 42), 157), "%.1fs" % t, HORIZONTAL_ALIGNMENT_LEFT, 60, 10, Color("68758d"))
	draw_line(Vector2(_x(playhead), 1), Vector2(_x(playhead), 142), Color("192541"), 2)

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		seek_requested.emit(clampf((event.position.x - 116) / maxf(size.x - 126, 1), 0, 1) * duration)
		accept_event()
