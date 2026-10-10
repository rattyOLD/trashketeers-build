class_name BattleQuality
extends RefCounted
## Упрощение оформления не меняет врагов, награды и опасные зоны.

static var level := 0
static var particle_scale := 1.0
static var light_limit := 24
static var light_divider := 4.0


static func configure(stage: int, lite: bool) -> void:
	level = clampi(stage, 0, 4)
	particle_scale = [1.0, 0.65, 0.4, 0.25, 0.15][level] * (0.65 if lite else 1.0)
	light_limit = mini(12 if lite else 24, [24, 12, 8, 5, 3][level])
	light_divider = [4.0, 4.0, 5.0, 6.0, 8.0][level]


static func particles(count: int) -> int:
	return maxi(0, int(ceil(count * particle_scale)))
