extends Node
## Бот-балансёр выживания: новичок (свежий сейв, стартовый ствол), уходит от толпы по кругу,
## берёт случайные карточки, навык по готовности. Без бессмертия и без воскрешения.
var main: Node
var t := 0.0
var started := false
var dead_logged := false
var rng := RandomNumberGenerator.new()
var orbit := 1.0
var last_wave := 0
var _hooked := false
var _wave_at := 0.0
var _last_level := 1
var _waves: Array[Dictionary] = []
var _levels: Array[Dictionary] = []
var _choices: Array[String] = []
var _peak_loot := 0
var _ending := false
var _last_trace_ms := 0
var _requested_scale := 3.0


func _ready() -> void:
	WeaponController.force_auto = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1
	seed(rng.seed)
	_requested_scale = float(OS.get_environment("SCALE")) if OS.get_environment("SCALE") != "" else 3.0
	Engine.time_scale = _requested_scale
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 16
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["tips_off"] = true
	var hero := OS.get_environment("HERO")
	if hero != "":
		SaveService.data["character"] = hero
	main = Node.new()
	main.set_script(load("res://scripts/main.gd"))
	get_tree().root.add_child.call_deferred(main)


func _physics_process(delta: float) -> void:
	if _ending:
		return
	t += delta
	if t > 0.6 and not started:
		started = true
		main._start_game(SaveService.get_selected_weapon())
	var screen: Node = main._screen
	if screen == null or not screen is Game:
		return
	var game := screen as Game
	if not _hooked:
		_hooked = true
		# Game.start randomizes production runs; seed the measured battle after it finishes.
		seed(rng.seed)
		game.director.wave_cleared.connect(func(number: int) -> void:
			var row := {"wave": number, "duration": game.director.elapsed - _wave_at, "at": game.director.elapsed, "level": game.level, "hp": game.player.hp, "coins": game.nuts, "ground": game.pickups.get_count(), "adapt": game.director.adapt}
			_waves.append(row)
			print("PACE_CLEAR ", JSON.stringify(row)))
	if game.player == null or not is_instance_valid(game.player):
		return
	var p := game.player
	# Combat hitstop returns production time to 1x. Resume the requested test speed after it.
	if not game._hitstop_active:
		Engine.time_scale = _requested_scale
	if OS.get_environment("PACE_TRACE") == "1" and Time.get_ticks_msec() - _last_trace_ms >= 30000:
		_last_trace_ms = Time.get_ticks_msec()
		print("PACE_TRACE elapsed=%.1f wave=%d paused=%s hp=%.1f loot=%d" % [game.director.elapsed, last_wave, get_tree().paused, p.hp, game.pickups.get_count()])
	if not p.has_meta("hooked"):
		p.set_meta("hooked", true)
		if OS.get_environment("DMG_LOG") == "1":
			p.damaged.connect(func(a: float) -> void: print("DMG t=%.1f %.1f src=%s hp=%.0f" % [t, a, Player.last_source, p.hp]))
		p.died.connect(func() -> void: print("DIED_SIGNAL t=%.1f hp=%.0f" % [t, p.hp]))
	if game.director.wave_number != last_wave:
		last_wave = game.director.wave_number
		_wave_at = game.director.elapsed
		print("WAVE %d t=%ds hp=%d/%d lvl=%d kills=%d power=%.2f adapt=%.2f" % [last_wave, int(game.director.elapsed), int(p.hp), int(p.max_hp), game.level, game.kills, game.stats.power(), game.director.adapt])
	_peak_loot = maxi(_peak_loot, game.pickups.get_count())
	if game.level != _last_level:
		_last_level = game.level
		_levels.append({"level": game.level, "at": game.director.elapsed, "wave": last_wave})
	if p.is_dead:
		if not dead_logged:
			dead_logged = true
			_finish(game, "DEAD")
		return
	if get_tree().paused:
		for node in game.get_children():
			if node is ChoiceCard and not node._done:
				node._opened_ms = 0
				node._pick(rng.randi_range(0, 1))
				return
			if node is RunEncounter and not node._resolved:
				node._resolve(rng.randf() < 0.5)
				return
		if game.hud._level_up.visible:
			game.hud._level_up._armed_at = 0
			if game._dealer_open:
				game._on_reroll_requested()
			else:
				var choices := game.hud._level_up._choices
				if not choices.is_empty():
					var index := rng.randi_range(0, choices.size() - 1)
					_choices.append(String(choices[index].id))
					game.hud._level_up._pick(index)
		return
	# Уход от толпы: от взвешенного центра ближних врагов + обход по кругу; изредка меняем сторону.
	var away := Vector2.ZERO
	for enemy in game.enemies.get_active():
		var d := enemy.global_position - p.global_position
		var dist := d.length()
		if dist < 420.0 and dist > 1.0:
			away -= d / dist * (420.0 - dist) / 420.0
	# Уклонение: из телеграфов анти-кемпера (молния, кислота, лазер) и из точек падения снарядов.
	var h := game.hazards
	for k in h.CAPACITY:
		if h._life[k] < 0.0:
			continue
		var to_me := p.global_position - h._pos[k]
		if h._kind[k] == HazardDirector.Kind.LASER:
			var side := to_me.dot(h._dir[k].orthogonal())
			if absf(side) < 90.0:
				away += h._dir[k].orthogonal() * signf(side + 0.01) * 3.0
		else:
			var r := (HazardDirector.SHOCK_RADIUS if h._kind[k] == HazardDirector.Kind.SHOCK else HazardDirector.ACID_RADIUS) + 50.0
			if to_me.length() < r:
				away += to_me.normalized() * 3.0
	# Пули врагов, летящие в нашу сторону: шаг вбок от линии полёта (реакция ~человеческая, не идеальная).
	var dodge_skill := float(OS.get_environment("DODGE")) if OS.get_environment("DODGE") != "" else 0.6
	for b in BulletPool._active:
		if b.team != Bullet.Team.ENEMY:
			continue
		var rel := p.global_position - b.global_position
		var dist := rel.length()
		if dist > 220.0 or b.velocity.length_squared() < 1.0:
			continue
		var dir := b.velocity.normalized()
		if rel.dot(dir) <= 0.0:
			continue
		var side := rel.dot(dir.orthogonal())
		if absf(side) < 40.0:
			away += dir.orthogonal() * signf(side + 0.01) * 2.0 * dodge_skill
	var lp := game.lobs
	for k in lp.CAPACITY:
		if lp._time[k] < 0.0:
			continue
		var to_me := p.global_position - lp._to[k]
		if to_me.length() < lp._radius[k] + 40.0:
			away += to_me.normalized() * 3.0
	if rng.randf() < delta * 0.25:
		orbit = -orbit
	var move := away.normalized() + away.orthogonal().normalized() * 0.6 * orbit if away.length() > 0.05 else Vector2.from_angle(t * 0.5) * 0.6
	# Спокойно рядом — идём за ближайшим опытом/монетами (до 600 px).
	if away.length() < 0.3:
		var best := Vector2.ZERO
		var best_d := 600.0
		var pm := game.pickups
		for i in pm._count:
			var d := pm._pos[i].distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = pm._pos[i] - p.global_position
		if best != Vector2.ZERO:
			move = move * 0.3 + best.normalized()
	# Держимся ближе к центру арены, чтобы не зажали в углу.
	var center := game.map.bounds.get_center() - p.global_position
	move += center / maxf(game.map.bounds.size.length() * 0.35, 1.0)
	if game.director.phase == WaveDirector.Phase.PORTAL and is_instance_valid(game._portal):
		move = (game._portal.global_position - p.global_position).normalized()
	# Управление как у игрока — через джойстик (бой сам переписывает move_input из джойстика каждый кадр).
	game.hud.joystick._touch_index = 99
	game.hud.joystick.output = move.limit_length(1.0)
	game._request_skill()
	if game.director.elapsed >= float(OS.get_environment("DURATION") if OS.get_environment("DURATION") != "" else "900"):
		_finish(game, "TIMEOUT")


func _finish(game: Game, outcome: String) -> void:
	_ending = true
	var report := {"seed": rng.seed, "outcome": outcome, "wave": last_wave, "time": game.director.elapsed, "level": game.level, "kills": game.kills, "coins": game.nuts, "power": game.stats.power(), "peak_loot": _peak_loot, "waves": _waves, "levels": _levels, "choices": _choices, "by": Player.last_source}
	print(outcome, " wave=%d t=%ds lvl=%d kills=%d by=%s" % [last_wave, int(game.director.elapsed), game.level, game.kills, Player.last_source])
	print("PACE_REPORT ", JSON.stringify(report))
	var output := OS.get_environment("PACE_OUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	get_tree().paused = false
	game.queue_free()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1, true, false, true).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	get_tree().quit()
