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
	return [{"title": title, "progress": progress, "goal": goal, "done": completed}]
