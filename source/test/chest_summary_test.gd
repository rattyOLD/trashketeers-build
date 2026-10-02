extends Node
## Итог сундука с 80 наградами: рамка помещается в экран, «ЗАБРАТЬ» видна, награды склеены.

func _ready() -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(720, 1280)
	add_child(sub)
	var rewards: Array[Dictionary] = []
	for i in 40:
		rewards.append({"type": "coins", "amount": 100 + i, "title": "x", "rarity": "common"})
		rewards.append({"type": "shard", "key": "k%d" % (i % 4), "amount": 2, "rarity": "rare", "title": "Чертёж ×2", "subtitle": "Оружие %d" % (i % 4)})
	var reveal := ChestReveal.new(rewards, "rare", Color("#a46bff"), "РЕДКИЙ СУНДУК")
	sub.add_child(reveal)
	await get_tree().process_frame
	reveal._show_summary()
	await get_tree().create_timer(0.8).timeout
	var merged := reveal._merged_rewards()
	var panel: Control = reveal._stack.get_child(reveal._stack.get_child_count() - 1)
	var rect := panel.get_global_rect()
	var ok := merged.size() == 5 and rect.position.y >= 0.0 and rect.end.y <= 1280.5
	print("MERGED %d PANEL %.0f..%.0f" % [merged.size(), rect.position.y, rect.end.y])
	print("CHEST_SUMMARY_TEST ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
