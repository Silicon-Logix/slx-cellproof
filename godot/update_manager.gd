# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends Node
## Explicit update checks against the product repository. No background network checks.

const OWNER_REPO := "Silicon-Logix/slx-cellproof"
const API_URL := "https://api.github.com/repos/" + OWNER_REPO + "/releases?per_page=20"
const RELEASES_URL := "https://github.com/" + OWNER_REPO + "/releases"
const MAX_INSTALLER := 250 * 1024 * 1024
const Storage = preload("res://project_storage.gd")
var app: Control
var dialog: AcceptDialog
var message: Label
var action: Button
var metadata_request: HTTPRequest
var download_request: HTTPRequest
var phase := ""
var candidate: Dictionary = {}
var download_path := ""
var verified_path := ""
var expected_sha256 := ""
var signed_document: Dictionary = {}
var signer_thumbprint := ""
var production := false

func attach(owner_app: Control) -> void:
	app = owner_app
	production = ProjectSettings.get_setting("application/config/release_channel", "development-preview") == "production"
	dialog = AcceptDialog.new()
	dialog.title = "CellProof updates"
	dialog.min_size = Vector2i(650, 250)
	dialog.ok_button_text = "Close"
	var content: VBoxContainer = app._vbox(12)
	message = app._label("Check the official repository for a newer version.", 15)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message)
	action = app._button("Check for updates", _action, true)
	content.add_child(action)
	content.add_child(app._button("Open official releases", func(): OS.shell_open(RELEASES_URL)))
	dialog.add_child(app._margin(content, 20))
	app.add_child(dialog)
	metadata_request = HTTPRequest.new()
	metadata_request.timeout = 20
	metadata_request.body_size_limit = 1024 * 1024
	metadata_request.request_completed.connect(_metadata_complete)
	add_child(metadata_request)
	download_request = HTTPRequest.new()
	download_request.timeout = 120
	download_request.body_size_limit = MAX_INSTALLER
	download_request.max_redirects = 8
	download_request.request_completed.connect(_download_complete)
	add_child(download_request)

static func version_key(tag: String) -> Array[int]:
	var result: Array[int] = []
	var core := tag.trim_prefix("v").split("-")[0].split(".")
	if core.size() != 3 or tag.length() > 64:
		return result
	for part in core:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 100000:
			return []
		result.append(int(part))
	result.append(0 if tag.contains("-") else 1)
	return result

static func newer(a: String, b: String) -> bool:
	var first := version_key(a)
	var second := version_key(b)
	if first.size() != 4 or second.size() != 4:
		return false
	for index in range(4):
		if first[index] != second[index]:
			return first[index] > second[index]
	return false

static func valid_asset(asset: Variant, tag: String) -> bool:
	if not asset is Dictionary or not asset.get("name") is String or not asset.get("digest") is String:
		return false
	var name: String = asset.name
	var expected := "https://github.com/" + OWNER_REPO + "/releases/download/" + tag.uri_encode() + "/" + name.uri_encode()
	var digest: String = asset.digest
	return name.begins_with("slx-cellproof-") and name.ends_with("-windows-x64-setup.exe") and name.validate_filename() == name and asset.get("browser_download_url") == expected and digest.begins_with("sha256:") and digest.length() == 71 and digest.substr(7).is_valid_hex_number(false) and (asset.get("size") is float or asset.get("size") is int) and asset.size > 0 and asset.size <= MAX_INSTALLER

func show_updates() -> void:
	dialog.popup_centered()

func check() -> void:
	if phase != "":
		return
	show_updates()
	message.text = "Checking official CellProof releases…"
	action.disabled = true
	phase = "releases"
	var error := metadata_request.request(API_URL, PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: SLX-CellProof"]))
	if error != OK:
		fail("The update service could not be reached. " + error_string(error))

func _action() -> void:
	if verified_path != "":
		app.projects.before_replacing(launch_installer)
	elif not candidate.is_empty():
		download()
	else:
		check()

func _metadata_complete(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		fail("No update information is available. Check the official releases page or try again later.")
		return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		fail("The release service returned invalid metadata")
		return
	if phase == "manifest":
		if not parser.data is Dictionary:
			fail("The signed update manifest is invalid")
			return
		signed_document = parser.data
		app.core.request("update.verify", {"document": signed_document})
		return
	if not parser.data is Array:
		fail("The release service returned an unexpected response")
		return
	candidate = {}
	var current: String = ProjectSettings.get_setting("application/config/version")
	if not production:
		current += "-preview"
	for release in parser.data:
		if not release is Dictionary or release.get("draft", true) or (production and release.get("prerelease", true)) or not release.get("tag_name") is String or not release.get("assets") is Array:
			continue
		var tag: String = release.tag_name
		if not newer(tag, current) or (not candidate.is_empty() and not newer(tag, candidate.tag)):
			continue
		for asset in release.assets:
			if valid_asset(asset, tag):
				candidate = {"tag": tag, "asset": asset, "assets": release.assets}
	phase = ""
	action.disabled = false
	if candidate.is_empty():
		message.text = "CellProof %s is up to date for this channel. No newer installer with a published SHA-256 was found." % ProjectSettings.get_setting("application/config/version")
		action.text = "Check again"
	else:
		message.text = "CellProof %s is available. The installer will be downloaded from the official repository and checked against its published SHA-256.\n\n%s" % [candidate.tag, "A signed update manifest and a valid Windows publisher signature are required." if production else "Preview policy: publisher signing is not configured. The checksum verifies download integrity."]
		action.text = "Download verified installer"

func download() -> void:
	if candidate.is_empty() or phase != "":
		return
	action.disabled = true
	expected_sha256 = str(candidate.asset.digest).substr(7).to_lower()
	if production:
		for asset in candidate.assets:
			if asset is Dictionary and asset.get("name") == "update-manifest.json":
				var expected := "https://github.com/" + OWNER_REPO + "/releases/download/" + str(candidate.tag).uri_encode() + "/update-manifest.json"
				if asset.get("browser_download_url") == expected:
					phase = "manifest"
					if metadata_request.request(expected) != OK:
						fail("Cannot download the signed update manifest")
					return
		fail("This release has no signed update manifest. Installation was not started.")
	else:
		_begin_download()

func handle_response(operation: String, result: Dictionary) -> void:
	if operation != "update.verify" or phase != "manifest":
		return
	var payload: Variant = signed_document.get("payload")
	if not result.get("signature_valid", false) or not payload is Dictionary or not payload.get("files") is Dictionary or payload.files.get(candidate.asset.name) != expected_sha256 or str(payload.get("version", "")) != str(candidate.tag).trim_prefix("v") or not payload.get("authenticode_thumbprint") is String:
		fail("Signed metadata does not match this installer or release version")
		return
	signer_thumbprint = payload.authenticode_thumbprint
	if signer_thumbprint.length() != 40 or not signer_thumbprint.is_valid_hex_number(false):
		fail("The signed publisher identity is invalid")
		return
	_begin_download()

func _begin_download() -> void:
	var folder := ProjectSettings.globalize_path("user://updates/" + str(candidate.tag).validate_filename())
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		fail("Cannot create the local update download folder")
		return
	download_path = folder.path_join(str(candidate.asset.name) + ".download")
	download_request.download_file = download_path
	phase = "download"
	message.text = "Downloading %s…" % candidate.tag
	if download_request.request(candidate.asset.browser_download_url) != OK:
		fail("Cannot start the installer download")

func _download_complete(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		fail("The installer download did not complete. Installation was not started.")
		return
	if FileAccess.get_sha256(download_path) != expected_sha256:
		DirAccess.remove_absolute(download_path)
		fail("Installer checksum mismatch. Installation was not started.")
		return
	verified_path = download_path.trim_suffix(".download")
	if DirAccess.rename_absolute(download_path, verified_path) != OK:
		verified_path = ""
		fail("Cannot finalize the verified installer download")
		return
	phase = ""
	action.disabled = false
	action.text = "Install update…"
	message.text = "The installer checksum matches the official release. Save your project before continuing. Projects and recovery copies are preserved during installation.\n\n" + ("Windows publisher verification is required before launch." if production else "This is a preview update without publisher authentication.")

func launch_installer() -> void:
	if verified_path == "" or FileAccess.get_sha256(verified_path) != expected_sha256:
		fail("The prepared installer changed. Download it again.")
		return
	var helper := ProjectSettings.globalize_path("user://updates/CellProof-Update.ps1")
	if Storage.atomic_text(helper, FileAccess.get_file_as_string("res://content/CellProof-Update.ps1"), false) != OK:
		fail("Cannot prepare the verified update launcher")
		return
	var args := PackedStringArray(["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", helper, "-InstallerPath", verified_path, "-ExpectedSha256", expected_sha256, "-ParentProcessId", str(OS.get_process_id())])
	if production:
		args.append_array(PackedStringArray(["-ExpectedThumbprint", signer_thumbprint]))
	else:
		args.append("-AllowUnsignedPreview")
	if OS.create_process("powershell.exe", args) < 0:
		fail("The update launcher could not be started")
		return
	app.get_tree().quit()

func fail(text: String) -> void:
	phase = ""
	candidate = {}
	verified_path = ""
	signed_document = {}
	message.text = text
	action.text = "Check again"
	action.disabled = false

func operation_failed(operation: String, text: String) -> void:
	if operation == "update.verify":
		fail("Update verification failed. " + text)
