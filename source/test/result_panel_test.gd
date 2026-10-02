extends Node
## Рамка итогов не должна быть шире экрана, даже с длинным заголовком и длинными строками статистики.

func _ready() -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(540, 1170)
	add_child(sub)
	var panel := ResultPanel.new()
	sub.add_child(panel)
	await get_tree().process_frame
	panel.open(true, PackedStringArray(["Хладгор повержен!", "Неонит: +6 (всего 134)", "Урон по дракону: 123456", "Замерзал: ни разу не замёрз", "Без единой снежинки: ни разу не замёрз", "Чертёж: Призматический Бластер — получен!"]), "ГРАЦИОЗНО, КАК МУСОРНЫЙ БАК")
	await get_tree().create_timer(0.6).timeout
	var w := float(sub.size.x)
	var box: Control = panel._panel
	var rect := box.get_global_rect()
	var ok := rect.position.x >= 0.0 and rect.end.x <= w + 0.5
	print("VIEW %.0f PANEL %.0f..%.0f" % [w, rect.position.x, rect.end.x])
	print("RESULT_PANEL_TEST ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
