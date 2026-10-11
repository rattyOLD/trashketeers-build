class_name EnemyArt
extends RefCounted
## Плотность рисунка отделена от размера персонажа в мире и координат рига.
const CONFIG := "res://data/enemy_art.json"
static var _assets: Dictionary = {}
static var _loaded := false


static func density(path: String) -> float:
	if not _loaded:
		_loaded = true
		_assets = ConfigLoader.load_json(CONFIG).get("assets", {})
	return clampf(float((_assets.get(path, {}) as Dictionary).get("density", 1.0)), 1.0, 4.0)


static func logical_size(texture: Texture2D) -> Vector2:
	return texture.get_size() / density(texture.resource_path)
