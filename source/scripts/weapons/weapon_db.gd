extends Node
## Autoload "WeaponDB". Единая точка доступа к конфигам оружия.
## Перезагрузка атомарная: если новый JSON битый целиком, остаются старые данные.
## load_from_string() позволяет подтянуть конфиг с сервера (live-баланс без пересборки).

signal weapons_reloaded

const CONFIG_PATH := "res://data/weapons.json"
const SUPPORTED_VERSION := 1

var _weapons: Dictionary = {}
var _texture_cache: Dictionary = {}


func _ready() -> void:
	load_from_file(CONFIG_PATH)


func load_from_file(path: String) -> bool:
	var text := ConfigLoader.read_text(path)
	if text.is_empty():
		return false
	return load_from_string(text, path)


func load_from_string(json_text: String, source: String = "<string>") -> bool:
	var root := ConfigLoader.parse_root(json_text, source, SUPPORTED_VERSION, PackedStringArray(["weapons"]))
	if root.is_empty():
		return false

	var parsed := _build_weapons(root["weapons"], source)
	if parsed.is_empty():
		push_error("WeaponDB: в %s нет ни одного валидного оружия, данные не изменены" % source)
		return false

	_weapons = parsed
	weapons_reloaded.emit()
	return true


func get_weapon(weapon_id: StringName) -> WeaponData:
	var weapon: WeaponData = _weapons.get(weapon_id)
	if weapon == null:
		push_error("WeaponDB: оружие '%s' не найдено" % weapon_id)
	return weapon


func has_weapon(weapon_id: StringName) -> bool:
	return _weapons.has(weapon_id)


func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in _weapons:
		ids.append(key)
	return ids


func get_all() -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	for weapon in _weapons.values():
		list.append(weapon)
	return list


## Оружие, доступное игроку, в порядке из JSON.
func get_player_weapons() -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	for weapon in _weapons.values():
		if not weapon.enemy_only:
			list.append(weapon)
	return list


func _build_weapons(entries: Array, source: String) -> Dictionary:
	var result: Dictionary = {}
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("WeaponDB: элемент 'weapons' в %s не является объектом, пропущен" % source)
			continue
		var weapon := WeaponData.from_dict(entry, _resolve_texture)
		if weapon == null:
			continue
		if result.has(weapon.id):
			push_error("WeaponDB: дубликат weapon_id '%s' в %s, оставлена первая запись" % [weapon.id, source])
			continue
		result[weapon.id] = weapon
	return result


func _resolve_texture(path: String) -> Texture2D:
	return ConfigLoader.load_texture(path, _texture_cache)
