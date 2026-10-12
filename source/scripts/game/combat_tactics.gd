class_name CombatTactics
extends Node2D
## Two compatible tactics per run, three ranks each. Runtime work and fields are bounded.
const MAX_TACTICS := 2
const MAX_FIELDS := 10
const QUERY_LIMIT := 24
const CATALOG := {
	"arson": {"title": "Пиротехник", "color": "#f7a64b", "text": "Попадания поджигают, убийства оставляют огненные зоны на 3 с. Загоняй толпу в огонь. Прямой урон −8%."},
	"frost": {"title": "Ледокол", "color": "#88d8eb", "text": "Три попадания замораживают обычного врага. Замороженные враги разлетаются осколками при гибели. Боссы только замедляются. Прямой урон −8%."},
	"bankshot": {"title": "Бильярдист", "color": "#e5cb79", "text": "Пули отражаются от стен и усиливаются после отскока. Играй от углов и коридоров. Урон прямого попадания −15%."},
	"vanguard": {"title": "Авангард", "color": "#c6b0ee", "text": "После рывка по пройденному пути бьёт повторный разрез. Режь толпу насквозь. Дальность оружия −15%."},
	"sentry": {"title": "Окопник", "color": "#9acbae", "text": "Постой 1,2 с — поставишь турель. После ухода она работает ещё 3 с. Выбирай позицию и меняй её под угрозой. Скорость бега −6%."},
	"switcher": {"title": "Два ствола", "color": "#efb7cc", "text": "Смена оружия даёт 2,4 с усиленного огня и отбрасывающую волну. Перезарядка эффекта 4 с. Обычный урон −10%."},
}
var player: Player
var stats: RunStats
var fx: FxManager
var _find_target: Callable
var _clock := 0.0
var _tick_left := 0.0
var _proc_left := 0.0
var _kill_left := 0.0
var _swap_left := 0.0
var _still := 0.0
var _last_pos := Vector2.ZERO
var _dash_from := Vector2.ZERO
var _fields: Array[Dictionary] = []
var _frost_hits: Dictionary = {}
var _query: PhysicsShapeQueryParameters2D
var _busy := false
var _turret_left := 0.0
var _turret_at := Vector2.ZERO
var _turret_aim := Vector2.RIGHT
var _turret_shot := 0.0
var _turret_weapon: WeaponData
var _turret_source: WeaponData
var _shard_weapon: WeaponData
var shots_from_turret := 0
var shatters := 0
var echoes := 0

static func rank(run: RunStats, id: String) -> int:
	return clampi(roundi(run.get_stat(StringName("tactic_" + id))), 0, 3) if run != null else 0

static func selected(run: RunStats) -> PackedStringArray:
	var result := PackedStringArray()
	for id: String in CATALOG:
		if rank(run, id) > 0:
			result.append(id)
	return result

static func damage_factor(run: RunStats) -> float:
	var result := 1.0
	for id: String in ["arson", "frost", "bankshot", "switcher"]:
		if rank(run, id) > 0:
			result *= 0.85 if id == "bankshot" else (0.90 if id == "switcher" else 0.92)
	return result

static func title_line(run: RunStats) -> String:
	var names := PackedStringArray()
	for id in selected(run):
		names.append("%s %d/3" % [CATALOG[id]["title"], rank(run, id)])
	return " · ".join(names)

static func pair_hint(run: RunStats, id: String) -> String:
	var others := selected(run)
	if others.is_empty():
		return "Первая тактика · ещё одну можно добавить позже"
	if others.has(id):
		return "Следующий ранг: сильнее основной эффект"
	if (id == "arson" and others.has("frost")) or (id == "frost" and others.has("arson")):
		return "ТЕПЛОВОЙ УДАР: мороз по горящему врагу вызывает взрыв"
	if (id == "arson" and others.has("vanguard")) or (id == "vanguard" and others.has("arson")):
		return "ОГНЕННЫЙ СЛЕД: рывок оставляет огонь по пути"
	if (id == "bankshot" and others.has("frost")) or (id == "frost" and others.has("bankshot")):
		return "ЛЕДЯНОЙ БАНК: отскочившая пуля сразу замораживает обычного врага"
	if (id == "sentry" and others.has("switcher")) or (id == "switcher" and others.has("sentry")):
		return "ПЕРЕВООРУЖЕНИЕ: турель получает новое оружие и усиление смены"
	return "Вторая тактика дополняет первую · лимит две за забег"

func setup(actor: Player, run: RunStats, effects: FxManager, finder: Callable) -> void:
	player = actor
	stats = run
	fx = effects
	_find_target = finder
	_last_pos = player.global_position
	player.dash_started.connect(func() -> void: _dash_from = player.global_position)
	player.dash_ended.connect(_on_dash_ended)
	player.weapon_controller.slot_switched.connect(_on_swapped)
	player.weapon_controller.melee_contact.connect(_on_melee_contact)
	BulletPool.bullet_hit.connect(_on_hit)

func _physics_process(delta: float) -> void:
	if player == null or player.is_dead or get_tree().paused or not stats.has_tactics:
		return
	_clock += delta
	_proc_left = maxf(0.0, _proc_left - delta)
	_kill_left = maxf(0.0, _kill_left - delta)
	_swap_left = maxf(0.0, _swap_left - delta)
	if stats.switch_boost_left > 0.0:
		stats.switch_boost_left = maxf(0.0, stats.switch_boost_left - delta)
		if stats.switch_boost_left <= 0.0:
			player.weapon_controller.apply_run_stats(stats)
	for i in range(_fields.size() - 1, -1, -1):
		_fields[i]["left"] = float(_fields[i]["left"]) - delta
		if float(_fields[i]["left"]) <= 0.0:
			_fields.remove_at(i)
	var moved := player.global_position.distance_to(_last_pos)
	_last_pos = player.global_position
	_still = _still + delta if moved < 18.0 * delta and not player.is_dashing() else 0.0
	_tick_sentry(delta)
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = 0.3
		for field: Dictionary in _fields:
			_tick_field(field)
		for key: int in _frost_hits.keys():
			if _clock - float(_frost_hits[key]["time"]) > 4.0:
				_frost_hits.erase(key)
	queue_redraw()

func _near(at: Vector2, radius: float) -> Array[Enemy]:
	if _query == null:
		_query = PhysicsShapeQueryParameters2D.new()
		_query.shape = CircleShape2D.new()
		_query.collision_mask = PhysicsLayers.ENEMY
		_query.collide_with_areas = false
	(_query.shape as CircleShape2D).radius = radius
	_query.transform = Transform2D(0.0, at)
	var result: Array[Enemy] = []
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(_query, QUERY_LIMIT):
		var enemy := hit["collider"] as Enemy
		if enemy != null and enemy.is_alive():
			result.append(enemy)
	return result

func _on_hit(bullet: Bullet, target: Node2D) -> void:
	if not stats.has_tactics or bullet.team != Bullet.Team.PLAYER or bullet.tactic_generated or not target is Enemy or _busy:
		return
	_affect(target as Enemy, bullet.weapon.damage * bullet.damage_scale, bullet.wall_bounces > 0)

func _on_melee_contact(enemy: Enemy, damage: float) -> void:
	if stats.has_tactics and not _busy and enemy.is_alive():
		_affect(enemy, damage, false)

func _affect(enemy: Enemy, damage: float, bounced: bool) -> void:
	if not enemy.is_alive():
		return
	var fire_rank := rank(stats, "arson")
	var frost_rank := rank(stats, "frost")
	var burning := enemy.bleed_is_burn and enemy.bleed_left > 0.0
	if frost_rank > 0:
		var key := enemy.get_instance_id()
		if _frost_hits.size() < 64 or _frost_hits.has(key):
			var record: Dictionary = _frost_hits.get(key, {"hits": 0, "time": _clock})
			record["hits"] = int(record["hits"]) + 1
			record["time"] = _clock
			var freeze := int(record["hits"]) >= 3 or bounced and rank(stats, "bankshot") > 0
			enemy.add_slow(0.65 if enemy.data.is_boss() else (0.95 if freeze else 0.45), (0.65 + frost_rank * 0.15) if freeze else 1.2)
			if freeze:
				enemy.freeze(0.65 + frost_rank * 0.15)
				fx.ring(enemy.global_position, Color("#88d8eb"), enemy.data.radius + 12.0)
				record["hits"] = 0
			_frost_hits[key] = record
		if burning and fire_rank > 0 and _proc_left <= 0.0:
			_proc_left = 0.5
			_busy = true
			BulletPool.explode(enemy.global_position, 90.0 + frost_rank * 15.0, 16.0 + damage * 0.35, Bullet.Team.PLAYER, Color("#dcc6a8"), 0.5, &"ice")
			_busy = false
	if fire_rank > 0:
		enemy.add_bleed(5.0 * fire_rank + damage * 0.12, 2.4, true)

func enemy_died(enemy: Enemy) -> void:
	_frost_hits.erase(enemy.get_instance_id())
	if _busy or _kill_left > 0.0:
		return
	var fire_rank := rank(stats, "arson")
	var frost_rank := rank(stats, "frost")
	if fire_rank > 0:
		_add_field("fire", enemy.global_position, enemy.global_position, 92.0 + fire_rank * 12.0, 3.0, 6.0 * fire_rank)
	if frost_rank > 0 and enemy.slow_left > 0.0 and enemy.slow_amount >= 0.7:
		_shatter(enemy.global_position, frost_rank)
	if fire_rank > 0 or frost_rank > 0:
		_kill_left = 0.18

func _shatter(at: Vector2, tier: int) -> void:
	if _shard_weapon == null:
		_shard_weapon = WeaponDB.get_weapon(&"frost_shard_v1").duplicate_data()
		_shard_weapon.id = &"tactic_ice_shard"
		_shard_weapon.effect_color = Color("#9de1ec")
		_shard_weapon.damage = 9.0
		_shard_weapon.piercing = false
		_shard_weapon.ricochet_count = 0
		_shard_weapon.world_bounces = 0
		_shard_weapon.bullet_lifetime = 0.6
		_shard_weapon.max_distance = 340.0
		_shard_weapon.bullet_speed = 560.0
	shatters += 1
	for i in 4 + tier:
		var bullet := BulletPool.spawn(_shard_weapon, at, Vector2.from_angle(TAU * i / float(4 + tier)), Bullet.Team.PLAYER)
		if bullet != null:
			bullet.tactic_generated = true
			bullet.damage_scale = 1.0 + tier * 0.35
	fx.ring(at, Color("#9de1ec"), 60.0)

func _on_dash_ended(at: Vector2) -> void:
	var tier := rank(stats, "vanguard")
	if tier <= 0:
		return
	_add_field("echo", _dash_from, at, 42.0, 0.9, player.weapon_controller.weapon.damage * (0.55 + 0.2 * tier))
	if rank(stats, "arson") > 0:
		for i in 3:
			var point := _dash_from.lerp(at, float(i + 1) / 4.0)
			_add_field("fire", point, point, 60.0, 2.0, 8.0 * rank(stats, "arson"))

func _add_field(kind: String, at: Vector2, end: Vector2, radius: float, lifetime: float, damage: float) -> void:
	if _fields.size() >= MAX_FIELDS:
		_fields.pop_front()
	_fields.append({"kind": kind, "at": at, "end": end, "radius": radius, "left": lifetime, "damage": damage, "done": false})

func _tick_field(field: Dictionary) -> void:
	if field["kind"] == "echo":
		if bool(field["done"]) or float(field["left"]) > 0.65:
			return
		field["done"] = true
		echoes += 1
		var a: Vector2 = field["at"]
		var b: Vector2 = field["end"]
		for enemy in _near(a.lerp(b, 0.5), a.distance_to(b) * 0.5 + 50.0):
			var closest := Geometry2D.get_closest_point_to_segment(enemy.global_position, a, b)
			if closest.distance_squared_to(enemy.global_position) < pow(float(field["radius"]) + enemy.data.radius, 2.0):
				enemy.take_damage(float(field["damage"]), a.direction_to(b))
	else:
		for enemy in _near(field["at"], float(field["radius"])):
			enemy.add_bleed(float(field["damage"]), 0.6, true)

func _on_swapped(_previous: int, _current: int) -> void:
	var tier := rank(stats, "switcher")
	if tier <= 0 or _swap_left > 0.0 or player.weapon_controller.slots[_previous].id == player.weapon_controller.slots[_current].id:
		return
	_swap_left = 4.0
	stats.switch_boost_left = 2.4
	player.weapon_controller.apply_run_stats(stats)
	var at := player.global_position
	for enemy in _near(at, 110.0):
		enemy.push(at.direction_to(enemy.global_position) * (180.0 + tier * 45.0))
	fx.ring(at, Color("#efb7cc"), 110.0)

func _tick_sentry(delta: float) -> void:
	var tier := rank(stats, "sentry")
	if tier <= 0:
		return
	_turret_left = maxf(0.0, _turret_left - delta)
	if _still >= 1.2:
		if _turret_left <= 0.0 or player.global_position.distance_squared_to(_turret_at) > 140.0 * 140.0:
			_turret_at = player.global_position + Vector2(0, -32)
		_turret_left = 3.0
	if _turret_left <= 0.0:
		return
	_turret_shot -= delta
	if _turret_shot > 0.0 or not _find_target.is_valid():
		return
	var target: Node2D = _find_target.call(_turret_at, 480.0)
	if not is_instance_valid(target):
		return
	_turret_shot = maxf(0.22, 0.58 - tier * 0.09)
	var source := player.weapon_controller.weapon
	if _turret_weapon == null or _turret_source != source:
		_turret_source = source
		_turret_weapon = source.duplicate_data()
		_turret_weapon.id = &"tactic_sentry"
		_turret_weapon.damage = clampf(source.damage * 0.25, 8.0, 35.0) * (1.4 if stats.switch_boost_left > 0.0 else 1.0)
		_turret_weapon.bullet_radius = 5.0
		_turret_weapon.explosion_radius = 0.0
		_turret_weapon.ricochet_count = 0
		_turret_weapon.world_bounces = 0
		_turret_weapon.bullet_speed = 720.0
		_turret_weapon.max_distance = 520.0
		_turret_weapon.bullet_lifetime = 0.8
		_turret_weapon.piercing = false
		if _turret_weapon.bullet_texture == null:
			var fallback := WeaponDB.get_weapon(&"pistol_v1")
			_turret_weapon.bullet_texture = fallback.bullet_texture
			_turret_weapon.sprite_scale = fallback.sprite_scale
			_turret_weapon.bullet_modulate = Color("#9acbae")
	_turret_aim = _turret_at.direction_to(target.global_position)
	var bullet := BulletPool.spawn(_turret_weapon, _turret_at, _turret_aim, Bullet.Team.PLAYER)
	if bullet != null:
		bullet.tactic_generated = true
		shots_from_turret += 1

func clear_fields() -> void:
	_fields.clear()
	_frost_hits.clear()
	_turret_left = 0.0
	_still = 0.0
	var was_boosted := stats.switch_boost_left > 0.0
	stats.switch_boost_left = 0.0
	if was_boosted and is_instance_valid(player):
		player.weapon_controller.apply_run_stats(stats)
	queue_redraw()

func _draw() -> void:
	for field: Dictionary in _fields:
		var color := Color("#f7a64b") if field["kind"] == "fire" else Color("#c6b0ee")
		var alpha := clampf(float(field["left"]), 0.0, 1.0)
		if field["kind"] == "fire":
			draw_circle(field["at"], float(field["radius"]), Color(color, 0.14 * alpha))
			draw_arc(field["at"], float(field["radius"]), 0.0, TAU, 24, Color(color, 0.65 * alpha), 2.0)
		else:
			draw_line(field["at"], field["end"], Color(color, 0.3 * alpha), 28.0, true)
			draw_line(field["at"], field["end"], Color(color, 0.9 * alpha), 3.0, true)
	if _turret_left > 0.0 and player != null:
		draw_circle(_turret_at, 24.0, Color("#272b25"))
		draw_arc(_turret_at, 30.0, 0.0, TAU, 20, Color("#9acbae"), 2.0)
		WeaponIcons.draw(self, player.weapon_controller.weapon.icon, _turret_at, 0.48, _turret_aim.angle(), Color("#9acbae"))
