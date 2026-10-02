extends Node
## Баланс выживания: потолки бонусов работают, карточки не обещают одно, а дают другое, враги растут и после 20-й волны.

func _ready() -> void:
	var fails := 0
	# 1. потолки
	for key: StringName in RunStats.CAPS:
		var cap: float = RunStats.CAPS[key]
		if RunStats.capped(key, 1000.0) > cap + 0.0001 or RunStats.capped(key, cap * 0.5) != cap * 0.5:
			fails += 1
			print("FAIL cap ", key)
		var prev := -1.0
		for i in 200:
			var v := RunStats.capped(key, float(i) * cap * 0.05)
			if v < prev - 0.00001:
				fails += 1
				print("FAIL monotonic ", key)
				break
			prev = v
	# 2. всё взято на максимум + 200 «бесконечных» карточек
	var stats := RunStats.new()
	for u in ContentDB.get_upgrades():
		var n := u.max_stacks if u.max_stacks > 0 else 200
		for i in n:
			stats.apply(u)
	var dmg := 1.0 + stats.get_stat(&"damage_mult")
	var rate := 1.0 + stats.get_stat(&"fire_rate_mult")
	var shots := 1.0 + stats.get_stat(&"extra_projectiles")
	print("MAXED damage x%.2f rate x%.2f shots x%.0f crit %.0f%% resist %.0f%% speed +%.0f%%" % [dmg, rate, shots, stats.get_stat(&"crit_chance_add") * 100.0, stats.get_stat(&"damage_resist") * 100.0, stats.get_stat(&"move_speed_mult") * 100.0])
	if dmg > 4.01 or rate > 2.51 or shots > 8.01 or stats.get_stat(&"crit_chance_add") > 0.601 or stats.get_stat(&"damage_resist") > 0.501:
		fails += 1
		print("FAIL maxed too strong")
	# 3. тестерский флаг снимает потолок
	var god := RunStats.new()
	god.uncapped = true
	god.add_flat(&"damage_mult", 9.0)
	if god.get_stat(&"damage_mult") != 9.0:
		fails += 1
		print("FAIL uncapped")
	# 4. описание «+N%» совпадает со значением
	var re := RegEx.new()
	re.compile("^\\+(\\d+)%")
	for u in ContentDB.get_upgrades():
		var m := re.search(u.description)
		if m != null and u.stat != &"slow_chance" and u.stat != &"shock_chance" and u.stat != &"explosive_chance" and u.stat != &"bleed_chance" and u.stat != &"poison_chance" and u.stat != &"burn_chance" and u.stat != &"rail_ramp":
			var pct := int(m.get_string(1))
			if absi(pct - int(round(u.value * 100.0))) > 1 and u.value < 1.0 and u.value > 0.0:
				fails += 1
				print("FAIL desc ", u.id, " ", u.description, " value=", u.value)
	# 5. рост врагов
	var d := ContentDB.get_difficulty()
	for wave in [1, 20, 40, 80]:
		var late := maxf(float(wave) - float(d["late_start"]), 0.0)
		print("WAVE %d late hp x%.2f dmg x%.2f" % [wave, 1.0 + late * float(d["late_hp"]), 1.0 + late * float(d["late_damage"])])
	# 6. адаптивная сложность: только вверх, с потолком, монотонна по мощи
	var maxed_power := stats.power()
	for wave in [5, 20, 40, 80]:
		var prev_f := 0.0
		for pw in [1.0, 2.0, 4.0, 8.0, 16.0, 40.0, maxed_power]:
			var f := WaveDirector.adaptive_factor(pw, wave)
			if f < 1.0 or f > WaveDirector.ADAPT_MAX + 0.0001 or f < prev_f - 0.0001:
				fails += 1
				print("FAIL adapt wave=%d power=%.1f f=%.2f" % [wave, pw, f])
			prev_f = f
		print("ADAPT wave %d: weak(2) x%.2f mid(8) x%.2f strong(16) x%.2f maxed(%.0f) x%.2f" % [wave, WaveDirector.adaptive_factor(2.0, wave), WaveDirector.adaptive_factor(8.0, wave), WaveDirector.adaptive_factor(16.0, wave), maxed_power, WaveDirector.adaptive_factor(maxed_power, wave)])
	print("BALANCE_TEST ", "PASS" if fails == 0 else "FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
