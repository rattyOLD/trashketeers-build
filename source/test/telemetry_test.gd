extends Node
## NativeTelemetry против локального приёмника: старт, отчёт боя, ошибка скрипта из журнала.
func _ready() -> void:
	WeaponController.force_auto = true
	var t := NativeTelemetry.new()
	t.endpoint = "http://127.0.0.1:8899/"
	add_child(t)
	t.set_context("Game wave=3 enemies=12 fps=58")
	t.trail("экран Game")
	await get_tree().create_timer(1.0).timeout
	t.report("perf", "fps avg 58, 1% low 40 | test")
	push_error("Тестовая ошибка телеметрии")
	await get_tree().create_timer(7.0).timeout
	get_tree().quit()
