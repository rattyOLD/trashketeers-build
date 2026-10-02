extends Node
## Автотест серверной арены без сети: два бота бегают кругами, арена должна пройти волны, убить врагов и выдать итоги.
## Запуск: godot --headless --path . res://test/arena_test.tscn

func _ready() -> void:
	var arena := CoopArena.new()
	var ok := arena.setup(0, 12345)
	assert(ok)
	arena.add_player(11)
	arena.add_player(22)
	var cleared: Array[int] = []
	arena.wave_cleared.connect(func(n: int) -> void: cleared.append(n))
	var downs := [0]
	arena.player_downed.connect(func(_id: int) -> void: downs[0] += 1)
	var revives := [0]
	arena.player_revived.connect(func(_id: int) -> void: revives[0] += 1)
	var max_enemies := 0
	var steps := 0
	# 6 минут игрового времени, быстрее реального
	while steps < 30 * 360 and arena.phase != CoopArena.Phase.DONE:
		var t := float(steps) * CoopArena.TICK
		arena.set_input(11, Vector2.from_angle(t * 0.6))
		arena.set_input(22, Vector2.from_angle(t * 0.6 + 2.0) * 0.7)
		arena.tick()
		max_enemies = maxi(max_enemies, arena.alive_enemy_count())
		steps += 1
	var results := arena.results()
	print("ARENA steps=%d waves_cleared=%s max_enemies=%d downed=%d revived=%d finished=%s" % [steps, str(cleared), max_enemies, downs[0], revives[0], str(arena.phase == CoopArena.Phase.DONE)])
	print("RESULTS %s" % JSON.stringify(results))
	var snap := arena.snapshot()
	print("SNAPSHOT keys=%s p=%d e=%d" % [str(snap.keys()), (snap["p"] as Array).size(), (snap["e"] as Array).size()])
	# проверки
	var fails := 0
	if cleared.size() < 3:
		print("FAIL: волн пройдено мало")
		fails += 1
	for id: int in results["players"]:
		var r: Dictionary = results["players"][id]
		if int(r["kills"]) <= 0 or int(r["coins"]) > CoopArena.REWARD_COINS_CAP or int(r["xp"]) > CoopArena.REWARD_XP_CAP:
			print("FAIL: итоги игрока %d" % id)
			fails += 1
	# защита от мусорного ввода
	arena.set_input(11, Vector2(NAN, 5.0))
	arena.set_input(11, Vector2(9999.0, 9999.0))
	var p: Dictionary = arena.players[11]
	if Vector2(float(p["in_x"]), float(p["in_y"])).length() > 1.001:
		print("FAIL: ввод не обрезан")
		fails += 1
	print("ARENA_TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(0 if fails == 0 else 1)
