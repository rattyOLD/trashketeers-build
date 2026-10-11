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
	if delta <= 0.0:
		return value
	var displacement := value - target
	var decay := damping * 0.5
	var discriminant := stiffness - decay * decay
	var envelope := exp(-decay * delta)
	if discriminant > 0.0001:
		var frequency := sqrt(discriminant)
		var wave := sin(frequency * delta) / frequency
		var cosine := cos(frequency * delta)
		value = target + envelope * (displacement * cosine + (velocity + decay * displacement) * wave)
		velocity = envelope * (velocity * cosine - (decay * velocity + stiffness * displacement) * wave)
	elif discriminant < -0.0001:
		var root := sqrt(-discriminant)
		var slow := -decay + root
		var fast := -decay - root
		var first := (velocity - fast * displacement) / (slow - fast)
		var second := displacement - first
		value = target + first * exp(slow * delta) + second * exp(fast * delta)
		velocity = first * slow * exp(slow * delta) + second * fast * exp(fast * delta)
	else:
		var rate := velocity + decay * displacement
		value = target + envelope * (displacement + rate * delta)
		velocity = envelope * (velocity - decay * rate * delta)
	return value


func kick(impulse: float) -> void:
	velocity += impulse


func reset() -> void:
	value = 0.0
	velocity = 0.0
