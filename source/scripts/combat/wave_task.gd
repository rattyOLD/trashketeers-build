class_name WaveTask
extends RefCounted
## Необязательная цель волны. Не задерживает переход и не считает свиту главного босса.

var enemy_id := &""
var kind := &"kill"
var title := ""
var goal := 0
var progress := 0
var reward := 0
var completed := false


func start(spec: Dictionary) -> void:
	kind = StringName(spec.get("kind", "kill"))
	enemy_id = StringName(spec.get("enemy", ""))
	title = str(spec.get("title", ""))
	goal = maxi(0, int(spec.get("count", 0)))
	reward = clampi(int(spec.get("reward", 20)), 0, 30)
	progress = 0
	completed = false


## true ровно один раз — в момент выполнения.
func kill(id: StringName, boss_minion: bool) -> bool:
	if boss_minion or kind != &"kill" or enemy_id != id:
		return false
	return event(&"kill")


func event(event_kind: StringName, amount: int = 1) -> bool:
	if event_kind != kind or completed or goal <= 0 or amount <= 0:
		return false
	progress = mini(progress + amount, goal)
	completed = progress >= goal
	return completed


func rows() -> Array:
	if goal <= 0 or title.is_empty():
		return []
	return [{"title": title, "progress": progress, "goal": goal, "done": completed, "hint": hint(), "reward": reward}]


func hint() -> String:
	match kind:
		&"tower":
			return "Постой в круге неиспользованной вышки до полного заряда."
		&"break":
			return "Разбей объекты на карте выстрелами или ударами. Ящики с оружием не считаются."
		&"collect":
			return "Подбери монеты с земли. Награды за задания не считаются."
	return "Убери отмеченных противников. Свита главного босса не считается."


func accepts_target(target: Node2D) -> bool:
	if completed or goal <= 0 or not is_instance_valid(target):
		return false
	match kind:
		&"tower":
			return target is ChargeTower and not (target as ChargeTower).used
		&"break":
			return target is DestructibleObject and (target as DestructibleObject).kind == DestructibleObject.Kind.ART and (target as DestructibleObject).is_intact()
		&"kill":
			return target is Enemy and (target as Enemy).is_alive() and not (target as Enemy).boss_minion and (target as Enemy).data.id == enemy_id
	return false


## Переключаемся только на заметно более близкую цель, чтобы метка не дёргалась между соседями.
func nearest_target(origin: Vector2, candidates: Array, current: Node2D = null) -> Node2D:
	var best: Node2D = current if accepts_target(current) else null
	var distance := origin.distance_squared_to(best.global_position) * 0.75 if best != null else INF
	for candidate: Node2D in candidates:
		if candidate == current or not accepts_target(candidate):
			continue
		var next_distance := origin.distance_squared_to(candidate.global_position)
		if next_distance < distance:
			best = candidate
			distance = next_distance
	return best
