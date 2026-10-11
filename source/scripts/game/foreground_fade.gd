class_name ForegroundFade
extends Node
## Один контроллер прозрачности высоких объектов. Сам мир и источники света не исчезают.
const MIN_ALPHA := 0.27
const SCAN_INTERVAL := 0.12
var player: Node2D
var _timer := 0.0
var _active: Dictionary = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


static func register(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return
	var height := sprite.get_rect().size.y * absf(sprite.scale.y)
	if height >= 90.0:
		sprite.add_to_group(&"foreground_cover")


static func covers(sprite: Sprite2D, feet: Vector2) -> bool:
	if not sprite.is_visible_in_tree() or sprite.global_position.y <= feet.y + 4.0:
		return false
	var area: Rect2 = sprite.global_transform * sprite.get_rect()
	# Проверяем голову и грудь: прозрачность нужна даже при открытом пространстве под навесом.
	return area.grow(8.0).intersects(Rect2(feet + Vector2(-22, -102), Vector2(44, 94)))


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if not is_instance_valid(player):
		_restore()
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = SCAN_INTERVAL
		for record: Dictionary in _active.values():
			record["covered"] = false
		for node in get_tree().get_nodes_in_group(&"foreground_cover"):
			var sprite := node as Sprite2D
			if not covers(sprite, player.global_position):
				continue
			var id := sprite.get_instance_id()
			if not _active.has(id):
				_active[id] = {"node": weakref(sprite), "base": sprite.self_modulate, "covered": true}
			_active[id]["covered"] = true
	for id in _active.keys():
		var record: Dictionary = _active[id]
		var sprite := (record["node"] as WeakRef).get_ref() as Sprite2D
		if sprite == null:
			_active.erase(id)
			continue
		var base: Color = record["base"]
		var target := base.a * (MIN_ALPHA if record["covered"] else 1.0)
		sprite.self_modulate.a = lerpf(sprite.self_modulate.a, target, 1.0 - exp(-10.0 * delta))
		if not record["covered"] and absf(sprite.self_modulate.a - base.a) < 0.002:
			sprite.self_modulate = base
			_active.erase(id)


func _restore() -> void:
	for record: Dictionary in _active.values():
		var sprite := (record["node"] as WeakRef).get_ref() as Sprite2D
		if sprite != null:
			sprite.self_modulate = record["base"]
	_active.clear()


func _exit_tree() -> void:
	_restore()
