extends Node
## Ищет места, где содержимое прокрутки шире окна (из-за этого появляется горизонтальный скролл/обрезка).
func _ready() -> void:
	Orient.portrait = false
	var makers := {
		"BattlePass": func() -> Control: return BattlePassPopup.new(),
		"Camp": func() -> Control: return CampPopup.new(),
		"Shop": func() -> Control: return MenuPopups.Shop.new(false),
		"Skins": func() -> Control: return MenuPopups.Shop.new(true),
		"Settings": func() -> Control: return MenuPopups.Settings.new(),
		"Daily": func() -> Control: return DailyPopup.new(),
		"Chests": func() -> Control: return ChestsPopup.new(),
		"Hero": func() -> Control: return HeroPopup.new(),
		"Armory": func() -> Control: return MenuPopups.Armory.new(),
		"Upgrades": func() -> Control: return MenuPopups.Upgrades.new(),
		"Achievements": func() -> Control: return MenuPopups.Achievements.new(),
		"Profile": func() -> Control: return MenuPopups.Profile.new(),
	}
	var bad := 0
	for key: String in makers:
		var popup := (makers[key] as Callable).call() as Control
		add_child(popup)
		if popup is GlassPopup:
			(popup as GlassPopup).open()
		await get_tree().create_timer(0.6).timeout
		var pn: Control = popup.get("_panel") as Control
		if pn != null and pn.get_combined_minimum_size().x > 700.0:
			print("POPUP-WIDE ", key, " min ", pn.get_combined_minimum_size().x)
			_culprits(pn, 600.0, 0)
		for sc in _scrolls(popup):
			var child := sc.get_child(0) as Control
			if child == null:
				continue
			var need := child.get_combined_minimum_size().x
			if need > sc.size.x + 1.0:
				bad += 1
				print("WIDE ", key, ": scroll ", sc.size.x, " content-min ", need)
				_culprits(child, sc.size.x, 0)
		popup.queue_free()
		await get_tree().process_frame
	print("HSCROLL_TEST bad=", bad)
	get_tree().quit()

func _scrolls(n: Node) -> Array[ScrollContainer]:
	var out: Array[ScrollContainer] = []
	if n is ScrollContainer:
		out.append(n)
	for c in n.get_children():
		out.append_array(_scrolls(c))
	return out

func _culprits(n: Control, limit: float, depth: int) -> void:
	var w := n.get_combined_minimum_size().x
	if w <= limit or depth > 16:
		return
	var deeper := false
	for c in n.get_children():
		if c is Control and (c as Control).visible and (c as Control).get_combined_minimum_size().x > limit:
			deeper = true
			_culprits(c, limit, depth + 1)
	if not deeper:
		for c in n.get_children():
			if c is Control:
				if c is VBoxContainer:
					for d in c.get_children():
						print("         sub ", d.get_class(), " min ", (d as Control).get_combined_minimum_size().x, " ", d.get("text") if d is Label else "")
				print("      child ", c.get_class(), " min ", (c as Control).get_combined_minimum_size().x, " ", c.get("text") if c is Label or c is Button else "")
		print("   culprit: ", n.get_class(), " ", n.name, " min ", w, " text=", n.get("text") if n is Label or n is Button else "")
