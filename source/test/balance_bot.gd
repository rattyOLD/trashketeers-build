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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1
	seed(rng.seed)
	Engine.time_scale = float(OS.get_environment("SCALE")) if OS.get_environment("SCALE") != "" else 3.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 16
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	var hero := OS.get_environment("HERO")
	if hero != "":
		SaveService.data["character"] = hero
	main = Node.new()
	main.set_script(load("res://scripts/main.gd"))
	get_tree().root.add_child.call_deferred(main)


func _physics_process(delta: float) -> void:
	t += delta
	if t > 0.6 and not started:
		started = true
		main._start_game(SaveService.get_selected_weapon())
	var screen: Node = main._screen
	if screen == null or not screen is Game:
		return
	var game := screen as Game
	if game.player == null or not is_instance_valid(game.player):
		return
	var p := game.player
	if not p.has_meta("hooked"):
		p.set_meta("hooked", true)
		if OS.get_environment("DMG_LOG") == "1":
			p.damaged.connect(func(a: float) -> void: print("DMG t=%.1f %.1f src=%s hp=%.0f" % [t, a, Player.last_source, p.hp]))
		p.died.connect(func() -> void: print("DIED_SIGNAL t=%.1f hp=%.0f" % [t, p.hp]))
	if game.director.wave_number != last_wave:
		last_wave = game.director.wave_number
		print("WAVE %d t=%ds hp=%d/%d lvl=%d kills=%d power=%.2f adapt=%.2f" % [last_wave, int(game.run_time if "run_time" in game else t), int(p.hp), int(p.max_hp), game.level, game.kills, game.stats.power(), game.director.adapt])
	if p.is_dead:
		if not dead_logged:
			dead_logged = true
			print("DEAD wave=%d chapter_wave=%d t=%ds lvl=%d kills=%d by=%s" % [game.director.wave_number, game.director.chapter_wave(), int(t), game.level, game.kills, Player.last_source])
			get_tree().create_timer(0.5, true, false, true).timeout.connect(get_tree().quit)
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
	# Управление как у игрока — через джойстик (бой сам переписывает move_input из джойстика каждый кадр).
	game.hud.joystick._touch_index = 99
	game.hud.joystick.output = move.limit_length(1.0)
	game._request_skill()
	if get_tree().paused and game._level_up_open:
		game.hud._level_up._pick(rng.randi() % 3)
	if t > float(OS.get_environment("DURATION") if OS.get_environment("DURATION") != "" else "900"):
		print("TIMEOUT wave=%d t=%ds" % [game.director.wave_number, int(t)])
		get_tree().quit()
