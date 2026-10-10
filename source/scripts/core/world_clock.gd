extends Node
## Время анимаций мира: останавливается вместе с деревом, включая выбор улучшения.
## Встроенный TIME шейдеров продолжает идти на паузе.
var elapsed := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	elapsed += delta
	RenderingServer.global_shader_parameter_set(&"world_time", elapsed)
