class_name AimAssist
extends RefCounted
## Ручная доводка: реальные точки попадания в конусе пальца, затем проверка укрытия.
## Ограниченный список не даёт плотной толпе создавать сотни физических лучей.
const MAX_CANDIDATES := 8

static func point(target: Node2D) -> Vector2:
	return target.get_aim_point() if target.has_method("get_aim_point") else target.global_position

static func select(targets: Array, origin: Vector2, direction: Vector2, max_distance: float, min_cos: float, clear_path: Callable = Callable(), nearest: bool = false) -> Node2D:
	if direction.length_squared() < 0.01 or max_distance <= 0.0:
		return null
	var dir := direction.normalized()
	var limit := max_distance * max_distance
	var candidates: Array[Node2D] = []
	var scores: Array[float] = []
	for item in targets:
		var target := item as Node2D
		if not is_instance_valid(target) or not target.has_method("is_targetable") or not target.is_targetable():
			continue
		var to := point(target) - origin
		var distance := to.length_squared()
		if distance < 1.0 or distance > limit:
			continue
		var cosine := dir.dot(to.normalized())
		if cosine < min_cos:
			continue
		# Направление важнее угрозы; при почти равном угле предпочитаем ближнюю цель.
		var score := distance / limit if nearest else 1.0 - cosine + 0.001 * distance / limit
		var index := 0
		while index < scores.size() and scores[index] <= score:
			index += 1
		if index >= MAX_CANDIDATES:
			continue
		candidates.insert(index, target)
		scores.insert(index, score)
		if candidates.size() > MAX_CANDIDATES:
			candidates.pop_back()
			scores.pop_back()
	for target in candidates:
		if not clear_path.is_valid() or clear_path.call(target):
			return target
	return null
