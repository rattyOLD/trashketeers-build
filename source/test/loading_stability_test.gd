extends Node
var failures := 0
class LogProbe:
	extends NativeTelemetry
	var received: Array[String] = []
	func _send_error(text: String) -> void:
		received.append(text)
func _ready() -> void:
	var probe := LogProbe.new()
	var path := "user://large-test.log"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("x".repeat(NativeTelemetry.LOG_READ_LIMIT - 17) + "\nERROR: проверка 🦝\n   at: resource.cpp:42\n")
	file.close()
	probe._scan_log_file(path)
	_check(probe._log_pos == NativeTelemetry.LOG_READ_LIMIT, "bounded read")
	_check(probe.received.is_empty(), "UTF8 fragment retained")
	probe._scan_log_file(path)
	_check(probe.received.size() == 1 and probe.received[0].contains("проверка 🦝") and probe.received[0].contains("resource.cpp:42"), "error and location across chunks")
	probe._scan_log_file(path)
	_check(probe.received.size() == 1, "no duplicate scan")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("ERROR: rotated\n   at: new.cpp:9\n")
	file.close()
	probe._scan_log_file(path)
	_check(probe.received.size() == 2 and probe.received[1].contains("new.cpp:9"), "rotated log")
	file = FileAccess.open(path, FileAccess.WRITE)
	for i in 1024: file.store_string("большой журнал 🦝 ".repeat(256) + "\n")
	for i in 50: file.store_string("tail-%d\n" % i)
	file.close()
	var tail := NativeTelemetry._read_log_tail(path)
	_check(tail.contains("tail-49") and not tail.contains("tail-1\n") and tail.to_utf8_buffer().size() < NativeTelemetry.LOG_READ_LIMIT, "bounded crash tail")
	probe._log_pos = 0
	probe._scan_log_file(path)
	_check(probe._log_pos == NativeTelemetry.LOG_READ_LIMIT and probe._log_line.size() <= NativeTelemetry.LOG_LINE_LIMIT, "bounded long lines")
	probe.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(await WebResourcePacks.ensure(PackedStringArray(["world", "heroes"])), "native remains offline")
	var menu := MainMenuUI.new()
	add_child(menu)
	await get_tree().process_frame
	remove_child(menu)
	menu.resized.emit()
	menu._fit_menu()
	await get_tree().process_frame
	menu.free()
	print("LOADING_STABILITY failures=%d" % failures)
	get_tree().quit(failures)
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL loading stability: ", label)
