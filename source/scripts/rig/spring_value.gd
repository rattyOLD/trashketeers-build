class_name SpringValue
extends RefCounted
## Затухающая пружина для вторичной анимации: хвост, уши, голова и шарф «догоняют» движение
## тела с запаздыванием и перехлёстом, а не повторяют его покадрово.

var value := 0.0
var velocity := 0.0
var stiffness := 80.0
var damping := 8.0


func _init(spring_stiffness: float = 80.0, spring_damping: float = 8.0) -> void:
	stiffness = spring_stiffness
	damping = spring_damping


func update(target: float, delta: float) -> float:
	var dt := minf(delta, 1.0 / 30.0)
	velocity += (stiffness * (target - value) - damping * velocity) * dt
	value += velocity * dt
	return value


func kick(impulse: float) -> void:
	velocity += impulse


func reset() -> void:
	value = 0.0
	velocity = 0.0
