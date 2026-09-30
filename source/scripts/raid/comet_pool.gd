class_name CometPool
extends Node2D
## Пул ледяных комет (ТЗ: кометы только из Object Pool). Экземпляры создаются в setup()
## до начала боя. Устройство как у BulletPool: стек свободных + плотный массив активных
## со swap-remove. При нехватке комета просто не спавнится — лишняя комета не критична.

signal comet_impacted(position: Vector2, color: Color)

var _free: Array[Comet] = []
var _active: Array[Comet] = []


func setup(capacity: int) -> void:
	for i in capacity:
		var comet := Comet.new()
		comet.impacted.connect(_on_impacted)
		add_child(comet)
		_free.append(comet)


func spawn(at: Vector2, fall_time: float, damage: float, color: Color) -> bool:
	if _free.is_empty():
		return false
	var comet: Comet = _free.pop_back()
	comet.pool_index = _active.size()
	_active.append(comet)
	comet.activate(at, fall_time, damage, color)
	SoundManager.play(&"comet_fall")
	return true


func release_all() -> void:
	while not _active.is_empty():
		_release(_active.back())


func get_active_count() -> int:
	return _active.size()


func _physics_process(delta: float) -> void:
	var i := _active.size() - 1
	while i >= 0:
		if i < _active.size():
			var comet := _active[i]
			if not comet.tick(delta):
				_release(comet)
		i -= 1


func _release(comet: Comet) -> void:
	if comet.pool_index < 0:
		return
	var index := comet.pool_index
	var last: Comet = _active.pop_back()
	if last != comet:
		_active[index] = last
		last.pool_index = index
	comet.pool_index = -1
	comet.deactivate()
	_free.append(comet)


func _on_impacted(comet: Comet) -> void:
	comet_impacted.emit(comet.global_position, comet.tint)
