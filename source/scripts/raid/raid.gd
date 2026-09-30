class_name Raid
extends BattleBase
## Ивент-режим «Ледяной налёт»: замёрзшее озеро и ледяной дракон Хладгор.
## Победа — обнулить ХП дракона или продержаться DURATION секунд.
## Угрозы: конус морозного дыхания, хвостовая волна, ледяные осколки с лужами и озноб:
## шкала растёт в лужах и под дыханием, на 100% Енот замерзает. Ледяные щиты закрывают от дыхания и волны.
## Награда (неонит + чертёж Призматического Бластера) начисляется через SaveService.

const DURATION := 120.0
const COMET_CAPACITY := 28
const PLAYER_START := Vector2(0, 520)
const FALL_DEFEAT_DELAY := 0.4
const VICTORY_DELAY := 2.4
const DEFEAT_DELAY := 1.3
const DUST_COLOR := Color("#bff0ff")
const PUDDLE_CHILL := 34.0
const BREATH_CHILL := 42.0
const SHARD_CHILL := 30.0
const CHILL_DECAY := 11.0
const FREEZE_TIME := 1.3
const THAW_IMMUNITY := 2.2
const CHILL_SLOW := 0.42
const BLIZZARD_CHILL := 26.0
const BLIZZARD_PULSE_DAMAGE := 40.0
const THERMOS_USES := 2
const THERMOS_HEAL := 0.45
const THERMOS_COOLDOWN := 1.2
const PUDDLE_SLOW := 0.72

var arena: DragonArena
var props: ArenaProps
var comets: CometPool
var scorch: ScorchLayer
var laser: WhiteDragonLaser
var puddles: IcePuddles
var gauge: ChillGauge
var dragon: WhiteDragon
var warm: WarmCircles
var blizzard: BlizzardFx

var time_left := DURATION
var damage_dealt := 0.0

var _ending := false
var chill := 0.0
var _immunity := 0.0
var _frozen_left := 0.0
var _blizzard_on := false
var _freezes := 0
var _thermos_left := THERMOS_USES
var _thermos_cd := 0.0
var _thermos_button: Button
var _debug := false


func start(_weapon_id: StringName = &"") -> void:
	randomize()
	_build_layers()
	arena = DragonArena.new()
	layers.floor_layer.add_child(arena)
	scorch = ScorchLayer.new()
	layers.decals.add_child(scorch)
	comets = CometPool.new()
	layers.decals.add_child(comets)
	comets.setup(COMET_CAPACITY)
	puddles = IcePuddles.new()
	layers.decals.add_child(puddles)
	warm = WarmCircles.new()
	layers.decals.add_child(warm)
	blizzard = BlizzardFx.new()
	add_child(blizzard)

	_spawn_player(PLAYER_START, SaveService.get_loadout(), _find_target)
	gauge = ChillGauge.new()
	player.add_child(gauge)
	dragon = WhiteDragon.new()
	entities.add_child(dragon)
	laser = WhiteDragonLaser.new()
	layers.fx.add_child(laser)

	var bounds := Rect2(-Vector2.ONE * (DragonArena.RADIUS + 260.0), Vector2.ONE * (DragonArena.RADIUS + 260.0) * 2.0)
	_setup_common(bounds, Icons.star_dust())
	arena.build(layers, player)
	props = ArenaProps.new()
	props.build(layers.world)
	props.prop_smashed.connect(_on_prop_smashed)
	PlayerReflection.new().setup(player, layers.decals)
	var exclude: Array[RID] = [dragon.get_rid()]
	laser.setup(exclude, scorch)
	dragon.setup(player, arena, comets, laser, fx, layers)
	player.fell_into_void.connect(_on_player_fell)
	if SaveService.is_glow_enabled():
		add_child(RaidEnvironment.new())

	hud.configure_for_raid()
	hud.set_nuts(SaveService.get_star_dust())
	hud.show_boss("Хладгор · Хозяин Озера", dragon.hp, WhiteDragon.MAX_HP, true)
	hud.show_banner("ЛЕДЯНОЙ НАЛЁТ: ХЛАДГОР", Color("#bff6ff"), 2.4)
	_thermos_button = hud.add_thermos(_use_thermos)
	_update_thermos()
	_update_hud_timer()

	arena.crystal_destroyed.connect(_on_crystal_destroyed)
	comets.comet_impacted.connect(_on_comet_impacted)
	dragon.health_changed.connect(_on_dragon_health_changed)
	dragon.slammed.connect(_on_dragon_slammed)
	dragon.fury_started.connect(_on_fury_started)
	dragon.died.connect(_on_dragon_died)
	dragon.phase_changed.connect(_on_phase_changed)
	dragon.ultimate_warning.connect(_on_ultimate_warning)
	dragon.ultimate_started.connect(_on_ultimate_started)
	dragon.ultimate_finished.connect(_on_ultimate_finished)
	dragon.exhausted_started.connect(_on_exhausted)
	arena.ice_cracking.connect(_on_ice_cracking)
	arena.ice_dropped.connect(_on_ice_dropped)
	SoundManager.play_music(&"raid")
	Platform.haptic("heavy")


## Автоприцел бьёт только по дракону на земле: кристаллы — укрытие Енота, а не мишень.
func _find_target(from: Vector2, max_distance: float) -> Node2D:
	if dragon.is_targetable() and from.distance_squared_to(dragon.global_position) <= pow(max_distance + WhiteDragon.BODY_RADIUS, 2.0):
		return dragon
	return null


## Отладочный вход из браузера (#raidground, #raidtail, #raidfreeze): сразу на землю к нужной атаке.
func debug_setup(mode: String) -> void:
	_debug = true
	dragon._land()
	dragon._phase = WhiteDragon.Phase.GAP
	dragon._phase_timer = 0.3
	dragon._sequence_index = 1 if mode == "raidground" else 0
	if mode == "raidfreeze":
		_freeze()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		_use_thermos()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_thermos_cd = maxf(_thermos_cd - delta, 0.0)
	if _debug and player != null:
		player.hp = player.max_hp
	if _ending or finished or player == null or player.is_dead:
		return
	# Мёртвая зона: за краем R = 1000 стен нет — Енот падает в космос.
	if arena.is_in_void(player.global_position):
		player.fall_into_void()
		return
	_tick_chill(delta)
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_win(false)


func _tick_chill(delta: float) -> void:
	_immunity = maxf(_immunity - delta, 0.0)
	_frozen_left = maxf(_frozen_left - delta, 0.0)
	var in_puddle := puddles.contains(player.global_position)
	var rate := 0.0
	if in_puddle:
		rate += PUDDLE_CHILL
	if dragon.breath_hitting:
		rate += BREATH_CHILL
	var in_warm := warm.contains(player.global_position)
	if _blizzard_on and not in_warm:
		rate += BLIZZARD_CHILL
	if _immunity > 0.0:
		rate = 0.0
	if rate > 0.0:
		chill += rate * delta
	else:
		chill -= CHILL_DECAY * delta
	chill = clampf(chill, 0.0, 100.0)
	var slow := lerpf(1.0, CHILL_SLOW, chill / 100.0)
	player.move_slow = slow * (PUDDLE_SLOW if in_puddle else 1.0)
	gauge.value = chill
	var was_frozen := gauge.frozen
	gauge.frozen = _frozen_left > 0.0
	gauge.frozen_left = _frozen_left
	gauge.frozen_total = FREEZE_TIME
	if was_frozen and not gauge.frozen:
		_shatter_ice()
	var tint := Color.WHITE.lerp(Color(0.62, 0.86, 1.25), chill / 100.0 * 0.75)
	player.modulate = Color(0.5, 0.78, 1.3) if gauge.frozen else tint
	if chill >= 100.0 and _frozen_left <= 0.0:
		_freeze()


func _shatter_ice() -> void:
	var at := player.global_position + Vector2(0, -20)
	fx.burst(at, Color("#e8fbff"), 34, 420.0, 5.0)
	fx.burst(at, Color("#7fdcff"), 20, 300.0, 4.0)
	fx.ring(at, Color("#ffffff"), 130.0)
	_spawn_ice_shards(at)
	SoundManager.play(&"ice_blast", -3.0, true)
	add_shake(0.3)


func _spawn_ice_shards(at: Vector2) -> void:
	for i in 8:
		var shard := Sprite2D.new()
		shard.texture = ChillGauge.shard_texture(i % 4)
		shard.global_position = at
		shard.scale = Vector2.ONE * randf_range(0.45, 0.8)
		shard.rotation = randf() * TAU
		shard.z_index = 25
		add_child(shard)
		var dir := Vector2.from_angle(TAU * i / 8.0 + randf_range(-0.3, 0.3))
		var tween := shard.create_tween().set_parallel(true)
		tween.tween_property(shard, "global_position", at + dir * randf_range(90.0, 190.0) + Vector2(0, 40), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(shard, "rotation", shard.rotation + randf_range(-6.0, 6.0), 0.7)
		tween.tween_property(shard, "modulate:a", 0.0, 0.7).set_delay(0.25)
		tween.chain().tween_callback(shard.queue_free)


func _freeze() -> void:
	_freezes += 1
	chill = 30.0
	_frozen_left = FREEZE_TIME
	_immunity = FREEZE_TIME + THAW_IMMUNITY
	player.stun(FREEZE_TIME)
	fx.ring(player.global_position, Color("#bff0ff"), 130.0)
	fx.ring(player.global_position, Color("#ffffff"), 70.0)
	fx.burst(player.global_position + Vector2(0, -20), Color("#e8fbff"), 30, 340.0, 4.0)
	hud.show_banner("ЗАМОРОЖЕН! ЛЁД ТРЕЩИТ...", Color("#9ff6ff"), 0.9)
	SoundManager.play(&"ice_blast", 0.0, false)
	Platform.haptic("medium")
	add_shake(0.35)


func _use_thermos() -> void:
	if _ending or finished or player == null or player.is_dead or _thermos_left <= 0 or _thermos_cd > 0.0:
		return
	if player.hp >= player.max_hp and chill < 20.0:
		return
	_thermos_left -= 1
	_thermos_cd = THERMOS_COOLDOWN
	player.heal(player.max_hp * THERMOS_HEAL)
	chill = 0.0
	_immunity = maxf(_immunity, 1.0)
	fx.ring(player.global_position, Color("#ffb85c"), 110.0)
	fx.burst(player.global_position, Color("#ffd28a"), 18, 240.0, 4.0)
	SoundManager.play(&"shield_up", 0.0, false)
	Platform.haptic("medium")
	hud.show_banner("ТЕРМОС С ЧАЕМ! ОСТАЛОСЬ: %d" % _thermos_left, Color("#ffcf8a"), 1.0)
	_update_thermos()


func _update_thermos() -> void:
	if _thermos_button == null:
		return
	_thermos_button.text = "ТЕРМОС ×%d" % _thermos_left
	_thermos_button.disabled = _thermos_left <= 0


func _on_phase_changed(index: int, title: String) -> void:
	hud.set_boss_title("Хладгор · %s" % title)
	if index != 2:
		return
	hud.show_banner("ФАЗА II: %s" % title.to_upper(), Color("#9fe8ff"), 2.2)
	fx.ring(dragon.global_position, Color("#9fe8ff"), 300.0)
	add_shake(0.5)


func _on_ice_cracking() -> void:
	hud.show_banner("ЛЁД ТРЕЩИТ! ИДИ К ЦЕНТРУ", Color("#ffb0a0"), 2.2)
	add_shake(0.3)
	Platform.haptic("medium")


func _on_ice_dropped(_radius: float) -> void:
	add_shake(0.6)
	fx.ring(Vector2.ZERO, Color("#bff0ff"), _radius)


## Два тёплых круга: один поближе к Еноту, второй с другой стороны арены.
func _on_ultimate_warning() -> void:
	hud.show_banner("АБСОЛЮТНЫЙ НОЛЬ! ВСТАНЬ В ТЁПЛЫЙ КРУГ", Color("#ffcf8a"), 2.4)
	var limit := arena.safe_radius - WarmCircles.RADIUS - 40.0
	var base := player.global_position.angle() + randf_range(-1.1, 1.1)
	var points: Array[Vector2] = [
		Vector2.from_angle(base) * randf_range(300.0, maxf(limit, 320.0)),
		Vector2.from_angle(base + PI + randf_range(-0.5, 0.5)) * randf_range(300.0, maxf(limit, 320.0)),
	]
	warm.show_at(points)
	SoundManager.play(&"beam_charge", 0.0, false)


func _on_ultimate_started() -> void:
	_blizzard_on = true
	blizzard.set_active(true)
	add_shake(0.5)


func _on_ultimate_finished() -> void:
	var was_on := _blizzard_on
	_blizzard_on = false
	blizzard.set_active(false)
	if was_on and not _ending and not warm.contains(player.global_position):
		player.take_damage(BLIZZARD_PULSE_DAMAGE, Vector2.ZERO)
		fx.burst(player.global_position, Color("#e8fbff"), 22, 320.0, 4.0)
		add_shake(0.5)
	warm.hide_circles()


func _on_exhausted() -> void:
	hud.show_banner("ИЗНЕМОЖЕНИЕ! УРОН ×2 — БЕЙ!", Color("#ffe27a"), 2.0)
	SoundManager.play(&"star_dust", 0.0, false)


func _update_hud_timer() -> void:
	var color := UiStyle.DANGER if time_left <= 15.0 else UiStyle.TEXT
	hud.set_time_text(BattleBase.format_time(time_left, true), color)


func _on_crystal_destroyed(crystal: PrismCrystal) -> void:
	fx.ring(crystal.get_field_center(), Color("#9ff6ff"), 90.0)
	add_shake(0.2)


func _on_comet_impacted(at: Vector2, color: Color) -> void:
	puddles.spawn(at)
	if _immunity <= 0.0 and player.global_position.distance_to(at) < Comet.IMPACT_RADIUS * 1.25:
		chill = minf(chill + SHARD_CHILL, 100.0)
	fx.burst(at, color, 14, 320.0, 4.0)
	fx.ring(at, color, Comet.IMPACT_RADIUS)
	SoundManager.play(&"comet_impact")
	if player.global_position.distance_to(at) < Comet.IMPACT_RADIUS * 2.5:
		add_shake(0.25)


func _on_dragon_health_changed(hp: float, max_hp: float) -> void:
	var dealt := WhiteDragon.MAX_HP - hp
	if dealt > damage_dealt:
		fx.number(dragon.global_position + Vector2(randf_range(-40, 40), -110), dealt - damage_dealt)
	damage_dealt = dealt
	hud.update_boss(hp, max_hp)


func _on_dragon_slammed(_at: Vector2) -> void:
	add_shake(0.8)
	Platform.haptic("heavy")


func _on_fury_started() -> void:
	hud.set_boss_fury()
	hud.show_banner("ФАЗА III: АБСОЛЮТНАЯ СТУЖА", WhiteDragon.COLOR_FURY, 2.4)
	fx.ring(dragon.global_position, WhiteDragon.COLOR_FURY, 260.0)
	add_shake(0.6)
	props.smash(dragon.global_position)


func _on_prop_smashed(at: Vector2, height: float, tint: Color) -> void:
	fx.burst(at, ArenaProps.SNOW, 16, 320.0, 4.5)
	fx.chunks(at, tint, 7, 300.0, 6.0)
	fx.dust(at, 6, height * 0.5)
	fx.ring(at + Vector2(0, height * 0.3), Color(ArenaProps.SNOW, 0.7), height * 0.5)
	SoundManager.play(&"ice_blast", -9.0, true)
	add_shake(0.18)


func _on_dragon_died(at: Vector2) -> void:
	add_shake(1.0)
	fx.ring(at, Color.WHITE, 320.0)
	_win(true)


## Общая развязка победы: дракон повержен или Енот продержался 2 минуты.
func _win(dragon_killed: bool) -> void:
	if _ending or finished:
		return
	_ending = true
	BulletPool.release_all()
	comets.release_all()
	laser.hide_beam()
	if not dragon_killed:
		dragon.retreat()
	hud.hide_boss()

	var flawless := dragon_killed and _freezes == 0
	if flawless:
		SaveService.add_stat("raid_flawless")
	var reward := SaveService.record_raid_victory(dragon_killed)
	var drop_at := dragon.global_position if dragon_killed else player.global_position
	_play_loot_shower(drop_at)
	hud.set_nuts(SaveService.get_star_dust())
	hud.show_banner("ЗВЁЗДНАЯ ПЫЛЬ +%d" % reward["star_dust"], DUST_COLOR)

	var lines := PackedStringArray([
		"Хладгор повержен!" if dragon_killed else "Продержался %s в ледяной бурю!" % BattleBase.format_time(DURATION),
		"Неонит: +%d (всего %d)" % [reward["star_dust"], SaveService.get_star_dust()],
		"Чертёж: Призматический Бластер — получен!" if reward["blueprint_new"] else "Чертёж Призматического Бластера уже в коллекции",
		"Урон по дракону: %d" % roundi(damage_dealt),
		"Замерзал: %d" % _freezes,
	])
	if flawless:
		lines.append("Без единой снежинки: ни разу не замёрз!")
	if reward["blueprint_new"]:
		lines.append("Новая пушка «Призма» открыта в Оружейной")
	get_tree().create_timer(VICTORY_DELAY, false).timeout.connect(_show_result.bind(true, lines))


func _play_loot_shower(at: Vector2) -> void:
	SoundManager.play(&"star_dust", 0.0, false)
	fx.burst(at, DUST_COLOR, 60, 520.0, 5.0)
	fx.burst(at, Color.WHITE, 30, 380.0, 4.0)
	fx.ring(at, DUST_COLOR, 180.0)
	for i in 4:
		get_tree().create_timer(0.25 * (i + 1), false).timeout.connect(func() -> void:
			fx.burst(player.global_position + Vector2.from_angle(randf() * TAU) * 60.0, DUST_COLOR, 16, 260.0, 4.0)
			SoundManager.play(&"nut_pickup", 4.0))


func _on_player_fell() -> void:
	if _ending:
		return
	_ending = true
	laser.hide_beam()
	var lines := PackedStringArray([
		"Енот провалился под лёд",
		"Продержался: %s из %s" % [BattleBase.format_time(DURATION - time_left), BattleBase.format_time(DURATION)],
		"Урон по дракону: %d из %d" % [roundi(damage_dealt), roundi(WhiteDragon.MAX_HP)],
		"Лёд по краю трескается по фазам: держись ближе к центру",
	])
	get_tree().create_timer(FALL_DEFEAT_DELAY, false).timeout.connect(_show_result.bind(false, lines))


func _on_player_died() -> void:
	if _ending or player.is_falling:
		return
	_ending = true
	laser.hide_beam()
	fx.burst(player.global_position, UiStyle.DANGER, 40, 360.0, 5.0)
	add_shake(1.0)
	var survived := DURATION - time_left
	var lines := PackedStringArray([
		"Хладгор оказался сильнее",
		"Продержался: %s из %s" % [BattleBase.format_time(survived), BattleBase.format_time(DURATION)],
		"Урон по дракону: %d из %d" % [roundi(damage_dealt), roundi(WhiteDragon.MAX_HP)],
		"Совет: в метель вставай в тёплый круг, а после неё бей: дракон выдохся",
	])
	get_tree().create_timer(DEFEAT_DELAY, false).timeout.connect(_show_result.bind(false, lines))
