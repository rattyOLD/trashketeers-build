extends Node

var failures := 0
var updater: AppUpdater
var installer: TestInstaller
const PAYLOAD := "test APK payload"

class TestUpdater extends AppUpdater:
	var tester_result := ERR_CANT_OPEN
	var tester_requests := 0

	func _open_tester() -> Error:
		tester_requests += 1
		return tester_result

class TestInstaller extends RefCounted:
	signal installer_error(message: String)
	signal installer_opened
	var allowed := true
	var permission_requests := 0
	var installs := 0
	var installed_path := ""
	var installed_code := 0

	func can_install_packages() -> bool:
		return allowed

	func request_install_permission() -> bool:
		permission_requests += 1
		return true

	func install_apk(path: String, code: int) -> bool:
		installs += 1
		installed_path = path
		installed_code = code
		installer_opened.emit()
		return true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("APP_UPDATER FAIL: " + label)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


func _offer(code: int) -> void:
	updater._remote = {"code": code, "bytes": PAYLOAD.length(), "sha256": PAYLOAD.sha256_text()}
	updater._show("beta.%d" % code, "technical commit message must not be shown")
	updater._path = AppUpdater.UPDATE_DIR.path_join("TrashSquad-beta.%d.apk" % code)


func _dismiss() -> void:
	updater._popup.closed.emit()


func _click(button: Button) -> void:
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await get_tree().process_frame


func _run() -> void:
	updater = TestUpdater.new()
	add_child(updater)
	installer = TestInstaller.new()
	updater._native = installer
	installer.installer_opened.connect(updater._on_installer_opened)
	installer.installer_error.connect(updater._fail)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AppUpdater.UPDATE_DIR))
	_check(AppUpdater.valid_manifest({"sha256": PAYLOAD.sha256_text(), "bytes": PAYLOAD.length()}), "valid manifest")
	_check(not AppUpdater.valid_manifest({"sha256": "bad", "bytes": 100}), "invalid digest rejected")
	_check(not AppUpdater.valid_manifest({"sha256": "g".repeat(64), "bytes": 100}), "nonhex digest rejected")
	_check(not AppUpdater.valid_manifest({"sha256": PAYLOAD.sha256_text(), "bytes": AppUpdater.MAX_APK_BYTES + 1}), "oversized manifest rejected")
	get_tree().paused = false
	_offer(10)
	_check(get_tree().paused, "battle paused while updater is open")
	_check(not updater._status.text.contains("technical"), "commit text omitted")
	_write(updater._path + ".part", PAYLOAD)
	updater._stage = AppUpdater.Stage.DOWNLOADING
	updater._on_download(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray())
	_check(installer.installs == 1 and installer.installed_code == 10, "verified file opens installer")
	_check(installer.installed_path == ProjectSettings.globalize_path(updater._path), "installer gets absolute private path")
	_check(FileAccess.file_exists(updater._path) and not FileAccess.file_exists(updater._path + ".part"), "atomic rename after verification")
	_dismiss()
	_check(not get_tree().paused, "battle resumes after dismiss")
	_offer(10)
	updater._begin_download()
	_check(installer.installs == 2, "verified cached download reused")
	_dismiss()
	_offer(11)
	_write(updater._path + ".part", "corrupted APK")
	updater._stage = AppUpdater.Stage.DOWNLOADING
	updater._on_download(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray())
	_check(installer.installs == 2 and updater._stage == AppUpdater.Stage.ERROR, "corruption cannot reach installer")
	_check(not FileAccess.file_exists(updater._path + ".part"), "corrupted partial removed")
	_dismiss()
	_offer(12)
	_write(updater._path + ".part", PAYLOAD)
	updater._stage = AppUpdater.Stage.DOWNLOADING
	updater._on_download(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	_check(updater._stage == AppUpdater.Stage.ERROR and installer.installs == 2, "network failure stays retryable")
	_dismiss()
	get_tree().paused = true
	_offer(13)
	_write(updater._path + ".part", PAYLOAD)
	updater._stage = AppUpdater.Stage.DOWNLOADING
	_dismiss()
	_check(get_tree().paused, "previous pause restored")
	_check(not FileAccess.file_exists(updater._path + ".part"), "cancel removes partial")
	get_tree().paused = false
	_offer(14)
	_write(updater._path, PAYLOAD)
	installer.allowed = false
	updater._install()
	_check(updater._stage == AppUpdater.Stage.PERMISSION and installer.permission_requests == 1, "first install requests Android permission")
	installer.allowed = true
	updater._notification(NOTIFICATION_APPLICATION_RESUMED)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(installer.installs == 3 and installer.installed_code == 14, "return from settings continues installation")
	_dismiss()
	# Level-up already pauses the tree. The old root CanvasLayer inherited
	# PAUSABLE, disabling all its buttons; the updater layer must still receive input.
	get_tree().paused = true
	var old_layer := CanvasLayer.new()
	get_tree().root.add_child(old_layer)
	var old_button := Button.new()
	old_layer.add_child(old_button)
	_check(not old_button.can_process(), "old popup buttons stop processing during level-up pause")
	old_layer.queue_free()
	_offer(15)
	_write(updater._path, PAYLOAD)
	await get_tree().create_timer(0.8).timeout
	_check(updater._update.can_process(), "update button processes during existing pause")
	await _click(updater._update)
	_check(installer.installs == 4 and installer.installed_code == 15, "GUI click opens cached update installer while paused")
	await _click(updater._later)
	await get_tree().create_timer(0.3).timeout
	_check(not is_instance_valid(updater._popup) and get_tree().paused, "GUI later click closes popup and preserves level-up pause")
	updater._native = null
	_offer(16)
	await get_tree().create_timer(0.8).timeout
	await _click(updater._update)
	_check((updater as TestUpdater).tester_requests == 1 and updater._stage == AppUpdater.Stage.ERROR, "failed App Tester launch remains visible and retryable")
	_check(is_instance_valid(updater._popup) and not updater._update.disabled, "failed launch does not silently close popup")
	(updater as TestUpdater).tester_result = OK
	await _click(updater._update)
	await get_tree().create_timer(0.3).timeout
	_check((updater as TestUpdater).tester_requests == 2 and not is_instance_valid(updater._popup), "successful App Tester retry closes popup")
	get_tree().paused = false
	for code in range(10, 17):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AppUpdater.UPDATE_DIR.path_join("TrashSquad-beta.%d.apk" % code)))
	print("APP_UPDATER_TEST failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
