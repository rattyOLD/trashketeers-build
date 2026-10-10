extends Node
## Autoload "ContentDB": враги, карточки прокачки и главы (арена + 10 волн + босс каждая).
## Грузится после WeaponDB. Перезагрузка атомарная по каждому файлу.

signal content_reloaded

const ENEMIES_PATH := "res://data/enemies.json"
const UPGRADES_PATH := "res://data/upgrades.json"
const CHAPTERS_PATH := "res://data/chapters.json"
const SUPPORTED_VERSION := 1

## Волна — фиксированный «бюджет» count врагов: спавн пачками batch каждые spawn_interval,
## пока живых меньше max_alive. Волна очищена, когда бюджет исчерпан и все мертвы.
## mood — атмосфера волны (AtmosphereFX), boss — id босса, выходящего в начале волны.
const WAVE_DEFAULTS := {
	"count": 12,
	"spawn_interval": 1.0,
	"batch": 1,
	"max_alive": 30,
	"weights": {},
	"task": {},
	"mood": "clear",
	"boss": "",
	"miniboss": "",
	"title": "",
}

## Рост сложности: внутри главы — с каждой волной (HP/урон), после всех глав — круг заново жёстче.
const DIFFICULTY_DEFAULTS := {
	"hp_per_wave": 0.075,
	"damage_per_wave": 0.045,
	"speed_per_wave": 0.012,
	"loop_hp": 1.9,
	"loop_damage": 1.35,
	"loop_count": 1.25,
	"early_waves": 0,
	"early_count": 1.0,
	"early_damage": 1.0,
	"mini_hp": 1.0,
	"count_mult": 1.0,
	"alive_mult": 1.0,
	"interval_mult": 1.0,
	"loop_interval": 0.9,
	"loop_max_alive": 6,
	"intermission": 1.8,
	"late_start": 20.0,
	"late_hp": 0.04,
	"late_damage": 0.012,
}

var _enemies: Dictionary = {}
var _upgrades: Array[UpgradeData] = []
var _chapters: Array[Dictionary] = []
var _difficulty: Dictionary = DIFFICULTY_DEFAULTS.duplicate()
var _texture_cache: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> bool:
	var enemies_ok := _load_enemies()
	var upgrades_ok := _load_upgrades()
	var chapters_ok := _load_chapters()
	content_reloaded.emit()
	return enemies_ok and upgrades_ok and chapters_ok


func get_enemy(enemy_id: StringName) -> EnemyData:
	var enemy: EnemyData = _enemies.get(enemy_id)
	if enemy == null:
		push_error("ContentDB: враг '%s' не найден | %s" % [enemy_id, Platform.last_context()])
	return enemy


func get_enemy_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in _enemies:
		ids.append(key)
	return ids


func get_upgrades() -> Array[UpgradeData]:
	return _upgrades


## Главы по порядку: оформление арены, 10 волн (count, spawn_interval, batch, max_alive,
## weights, mood, boss), эскорт босса.
func get_chapters() -> Array[Dictionary]:
	return _chapters


func get_chapter(index: int) -> Dictionary:
	if _chapters.is_empty():
		return {}
	return _chapters[posmod(index, _chapters.size())]


func get_difficulty() -> Dictionary:
	return _difficulty


func _load_enemies() -> bool:
	var root := _read_root(ENEMIES_PATH, "enemies")
	if root.is_empty():
		return false
	var parsed: Dictionary = {}
	for entry in root["enemies"]:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var enemy := EnemyData.from_dict(entry, _resolve_texture)
		if enemy == null:
			continue
		if parsed.has(enemy.id):
			push_error("ContentDB: дубликат enemy_id '%s'" % enemy.id)
			continue
		parsed[enemy.id] = enemy
	if parsed.is_empty():
		return false
	_enemies = parsed
	return true


func _load_upgrades() -> bool:
	var root := _read_root(UPGRADES_PATH, "upgrades")
	if root.is_empty():
		return false
	var parsed: Array[UpgradeData] = []
	var seen: Dictionary = {}
	for entry in root["upgrades"]:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var upgrade := UpgradeData.from_dict(entry)
		if upgrade == null or seen.has(upgrade.id):
			continue
		seen[upgrade.id] = true
		parsed.append(upgrade)
	if parsed.is_empty():
		return false
	_upgrades = parsed
	return true


func _load_chapters() -> bool:
	var root := _read_root(CHAPTERS_PATH, "chapters")
	if root.is_empty():
		return false
	var parsed: Array[Dictionary] = []
	for raw in root["chapters"]:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var chapter: Dictionary = (raw as Dictionary).duplicate(true)
		var waves: Array[Dictionary] = []
		for entry in chapter.get("waves", []):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var wave := ConfigLoader.sanitize(entry, WAVE_DEFAULTS, "Wave")
			wave["weights"] = _valid_weights(wave["weights"])
			if wave["boss"] != "" and not _enemies.has(StringName(wave["boss"])):
				push_error("ContentDB: босс волны '%s' не найден, волна без босса" % wave["boss"])
				wave["boss"] = ""
			if wave["weights"].is_empty() and wave["boss"] == "":
				continue
			waves.append(wave)
		if waves.is_empty():
			push_error("ContentDB: глава '%s' без валидных волн пропущена" % chapter.get("id", "?"))
			continue
		chapter["waves"] = waves
		parsed.append(chapter)
	if parsed.is_empty():
		return false
	_chapters = parsed
	_difficulty = DIFFICULTY_DEFAULTS.duplicate()
	if typeof(root.get("difficulty")) == TYPE_DICTIONARY:
		_difficulty = ConfigLoader.sanitize(root["difficulty"], DIFFICULTY_DEFAULTS, "Difficulty")
	return true


func _valid_weights(weights: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in weights:
		var enemy_id := StringName(key)
		var weight = weights[key]
		if not _enemies.has(enemy_id):
			push_error("ContentDB: в волне неизвестный враг '%s'" % key)
			continue
		if not ConfigLoader.type_matches(weight, 1.0) or float(weight) <= 0.0:
			continue
		result[enemy_id] = float(weight)
	return result


func _read_root(path: String, list_key: String) -> Dictionary:
	var text := ConfigLoader.read_text(path)
	if text.is_empty():
		return {}
	return ConfigLoader.parse_root(text, path, SUPPORTED_VERSION, PackedStringArray([list_key]))


func _resolve_texture(path: String) -> Texture2D:
	return ConfigLoader.load_texture(path, _texture_cache)
