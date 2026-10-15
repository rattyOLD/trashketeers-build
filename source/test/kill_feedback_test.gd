extends Node
## Убийство через настоящий EnemyManager: пул, маркеры, серии, звук и движение останков.
var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("KILL_FEEDBACK: " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["quality"] = 0
	Orient.portrait = false
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	_test_audio()
	await _test_kills()
	for player in SoundManager._players: player.stop()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1, true, false, true).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	for frame in 4: await get_tree().process_frame
	print("KILL_FEEDBACK failures=", failures)
	get_tree().quit.call_deferred(1 if failures else 0)

func _test_audio() -> void:
	SoundManager.unlocked = true
	SoundManager._kill_ms = -100000
	SoundManager._budget = 1.0
	SoundManager._budget_ms = Time.get_ticks_msec()
	SoundManager._last_played_ms.clear()
	SoundManager.play(&"shot_smg")
	_check(not SoundManager._last_played_ms.has(&"shot_smg"), "gunfire leaves the final budget token for confirmation")
	SoundManager.play_kill(1)
	var confirm: AudioStreamPlayer = SoundManager._players[SoundManager.KILL_CHANNEL]
	_check(confirm.stream == SoundManager._streams[&"kill_confirm"], "confirmation starts with a nearly exhausted budget")
	_check(is_equal_approx(confirm.pitch_scale, 0.96), "first kill has a restrained base pitch")
	var remaining: float = SoundManager._budget
	for index in 200: SoundManager.play_kill(index + 1)
	_check(SoundManager._budget >= remaining, "simultaneous crowd kills do not start hundreds of audio sources")
	for index in 25:
		SoundManager._budget = SoundManager.SFX_BUDGET_BURST
		SoundManager._last_played_ms.clear()
		SoundManager.play(&"shot_smg")
	_check(confirm.stream == SoundManager._streams[&"kill_confirm"] and SoundManager._pick_player() < SoundManager.KILL_CHANNEL, "gunfire cannot replace the confirmation channel")
	SoundManager._kill_ms = -100000
	SoundManager._budget = SoundManager.SFX_BUDGET_BURST
	SoundManager.play_kill(100)
	_check(confirm.pitch_scale <= 1.211, "series pitch is capped")
	SoundManager._kill_ms = -100000
	SoundManager.play_kill(3, true)
	_check(confirm.stream == SoundManager._streams[&"k_perfect"], "elite kill uses a distinct confirmation")
	SoundManager._last_warning_ms = -100000
	SoundManager._budget = 0.0
	SoundManager._budget_ms = Time.get_ticks_msec()
	SoundManager.play_warning(&"beam_charge")
	_check(SoundManager._players.back().stream == SoundManager._streams[&"beam_charge"], "danger cue keeps its separate channel and priority")
	for player in SoundManager._players: player.stop()

func _test_kills() -> void:
	var game := Game.new()
	add_child(game)
	game.start()
	game.finished = true # Измеряем отклик без микропауз и случайных новых волн.
	game.set_physics_process(false)
	game.director.set_physics_process(false)
	game.events.set_physics_process(false)
	game.hazards.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.weapon_controller.set_physics_process(false)
	game.enemies.set_physics_process(false)
	game.enemies.release_all()
	game.hud._chapter_card.hide()
	var feed := game.hud.combat_feed
	feed.set_process(false)
	var at := game.player.global_position + Vector2(100, 0)
	var first := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), at)
	var source := first.get_sprite()
	var look: Color = source.shader_material.get_shader_parameter("tint")
	var before := game.fx._mk_next
	var fatal_weapon := WeaponDB.get_weapon(&"pistol_v1").duplicate_data()
	fatal_weapon.damage = 999.0
	fatal_weapon.crit_chance = 0.0
	fatal_weapon.knockback = 0.0
	var fatal := BulletPool.spawn(fatal_weapon, at - Vector2(40, 0), Vector2.RIGHT, Bullet.Team.PLAYER)
	fatal._apply_damage(first)
	BulletPool.release_all()
	_check(game.kills == 1 and game._multi == 1, "one lethal hit awards one kill and starts the series")
	_check(game.fx._mk_next == (before + 1) % FxManager.MARK_CAPACITY and game.fx._mk_kind[before] == 2, "lethal hit has a fixed kill marker")
	_check(game.fx._mk_target[before] == null, "kill marker stays at the defeat position instead of following a reused enemy")
	_check(game.fx._fc_vel[0].x > 0.0 and game.fx._fc_tint[0].is_equal_approx(look), "framed defeat carries hit direction and preserves the original look")
	var corpse_start: Vector2 = game.fx._fc_nodes[0].position
	game.fx._tick_frame_corpses(0.1)
	_check(game.fx._fc_nodes[0].position.x > corpse_start.x, "death animation visibly moves away from the lethal hit")
	var shot := Bullet.new()
	shot.weapon = WeaponDB.get_weapon(&"pistol_v1")
	shot.team = Bullet.Team.PLAYER
	var battle := BattleBase.new()
	battle.fx = game.fx
	battle.finished = true
	battle._on_bullet_hit(shot, first)
	_check(game.fx._mk_next == (before + 1) % FxManager.MARK_CAPACITY, "late projectile notification cannot cover the kill marker with an ordinary hit")
	shot.free()
	battle.free()
	var second := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), at + Vector2(0, 60))
	_check(second.last_hit_direction == Vector2.ZERO, "reused enemy resets its last hit direction")
	second.take_bullet(999.0, Vector2.LEFT, 1.0, false, false)
	_check(game.kills == 2 and game._multi == 2 and feed._chain == 2 and feed._medal == Game.MULTI_CALLS[2], "second kill advances the visible series and medal")
	var output := OS.get_environment("KILL_FEEDBACK_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		await get_tree().create_timer(0.08).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join("double-kill.png"))
	feed.set_process(false)
	feed._process(0.6)
	_check(feed._chain == 2 and feed._chain_left > 0.0, "series allows a short reposition between kills")
	feed.set_process(true)
	get_tree().paused = true
	var paused_left: float = feed._chain_left
	await get_tree().create_timer(0.08, true, false, true).timeout
	_check(is_equal_approx(feed._chain_left, paused_left), "pause preserves the series window")
	get_tree().paused = false
	feed.set_process(false)
	feed._process(0.7)
	_check(feed._chain == 0, "series expires visibly")
	game._multi_left = 0.0
	var third := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), at)
	third.take_damage(999.0)
	_check(game._multi == 1 and feed._chain == 1 and feed._total == 10 and feed._lines.is_empty(), "kill after the window starts a fresh series with fresh points; plain kills add no line")
	var start_kills := game.kills
	for index in 80:
		var enemy := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), at)
		enemy.take_bullet(999.0, Vector2.RIGHT, 1.0, false, false)
	_check(game.kills == start_kills + 80 and feed._lines.size() <= CombatFeed.MAX_LINES, "crowd deaths keep bounded feed and count all kills")
	_check(game.fx._fc_nodes.size() == FxManager.FRAME_CORPSE_POOL, "death animations reuse the fixed sprite pool")
	var active: int = game.kills
	var bomber := game.enemies.spawn(ContentDB.get_enemy(&"bomb_rat"), at)
	bomber.self_destructed = true
	bomber.died.emit(bomber)
	_check(game.kills == active, "self-destruction is not a confirmed player kill")
	# Непокадровые останки тоже имеют короткий импульс, ограниченный при большом delta.
	var corpse_index: int = game.fx._co_next
	game.fx.corpse(game.player.visual.get_ghost_texture(), Vector2.ZERO, Vector2.ONE, 1.0, Color.WHITE, 0, Vector2(10000, 0))
	game.fx.set_process(false)
	game.fx._process(0.5)
	_check(game.fx._co_pos[corpse_index].x > 0.0 and game.fx._co_pos[corpse_index].x < 30.0, "legacy corpse impulse is bounded even under a frame stall")
	game.free()
	BulletPool.release_all()
