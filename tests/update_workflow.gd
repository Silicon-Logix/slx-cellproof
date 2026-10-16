# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends SceneTree
const Updates = preload("res://update_manager.gd")
var checks := 0
var failed := false

func _initialize() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("UPDATE FAIL: " + message)
		quit(1)

func run() -> void:
	create_timer(25).timeout.connect(func(): push_error("Update workflow timeout"); quit(1))
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await app.core.response
	var updates: Node = app.updates
	expect(updates.phase == "", "startup performs no background update request")
	expect(Updates.newer("v0.6.0", "0.5.0") and not Updates.newer("v0.4.0", "0.5.0"), "semantic numeric versions enforce upgrade order")
	expect(Updates.newer("v0.5.0", "0.5.0-preview") and not Updates.newer("invalid", "0.5.0"), "release channel and malformed tags handled")
	var tag := "v99.0.0-preview"
	var name := "slx-cellproof-99.0.0-windows-x64-setup.exe"
	var asset := {"name": name, "digest": "sha256:" + "a".repeat(64), "size": 100,
		"browser_download_url": "https://github.com/Silicon-Logix/slx-cellproof/releases/download/" + tag + "/" + name}
	expect(Updates.valid_asset(asset, tag), "official installer requires a bounded size and published SHA-256")
	var unsafe := asset.duplicate()
	unsafe.browser_download_url = "https://other.example/installer.exe"
	expect(not Updates.valid_asset(unsafe, tag), "foreign installer origin rejected")
	unsafe = asset.duplicate()
	unsafe.digest = "sha256:unavailable"
	expect(not Updates.valid_asset(unsafe, tag), "missing or malformed integrity data rejected")
	unsafe = asset.duplicate()
	unsafe.size = Updates.MAX_INSTALLER + 1
	expect(not Updates.valid_asset(unsafe, tag), "oversized installer rejected")
	var release := [{"draft": false, "prerelease": true, "tag_name": tag, "assets": [asset]}]
	updates.phase = "releases"
	updates._metadata_complete(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(release).to_utf8_buffer())
	expect(updates.candidate.tag == tag, "preview channel offers the eligible official installer")
	updates.production = true
	updates.phase = "releases"
	updates._metadata_complete(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(release).to_utf8_buffer())
	expect(updates.candidate.is_empty(), "production channel excludes preview releases")
	updates.candidate = {"tag": tag, "asset": asset, "assets": [asset]}
	updates.download()
	expect(updates.phase == "" and updates.message.text.contains("no signed update manifest"), "production blocks unsigned metadata before any installer download")
	updates.production = false
	updates.candidate = {"tag": tag, "asset": asset, "assets": [asset]}
	var folder := ProjectSettings.globalize_path(app.projects.base + "updates")
	DirAccess.make_dir_recursive_absolute(folder)
	updates.download_path = folder.path_join("tampered.download")
	var file := FileAccess.open(updates.download_path, FileAccess.WRITE)
	file.store_string("tampered fixture")
	file.close()
	updates.expected_sha256 = "0".repeat(64)
	updates._download_complete(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray())
	expect(updates.verified_path == "" and not FileAccess.file_exists(updates.download_path), "checksum mismatch discards the prepared download without execution")
	updates.show_updates()
	expect(updates.dialog.visible and updates.action.text == "Check again", "verification failures remain readable and retryable")
	print("PASS: %d update policy GUI checks" % checks)
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
