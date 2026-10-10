class_name WaveTask
extends RefCounted
## Необязательная цель волны. Не задерживает переход и не считает свиту главного босса.

var enemy_id := &""
var title := ""
var goal := 0
var progress := 0
var reward := 0
var completed := false


func start(spec: Dictionary) -> void:
	enemy_id = StringName(spec.get("enemy", ""))
	title = str(spec.get("title", ""))
	goal = maxi(0, int(spec.get("count", 0)))
	reward = clampi(int(spec.get("reward", 20)), 0, 30)
	progress = 0
	completed = false


## true ровно один раз — в момент выполнения.
func kill(id: StringName, boss_minion: bool) -> bool:
	if boss_minion or completed or goal <= 0 or enemy_id != id:
		return false
	progress = mini(progress + 1, goal)
	completed = progress >= goal
	return completed


func rows() -> Array:
	if goal <= 0 or title.is_empty():
		return []
	return [{"title": title, "progress": progress, "goal": goal, "done": completed}]
