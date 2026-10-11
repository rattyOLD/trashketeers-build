class_name SceneryGround
extends Node2D
## Площадка, контактная тень и свет нарисованных ламп. Статичная геометрия, без процесса.
var tint := Color("#ffc26a")
var width := 320.0
var bank := false
var _mesh: ArrayMesh


func _ready() -> void:
	add_to_group(&"scenery_ground")
	light_mask = BiomeLayers.LIGHT_MASK_FLOOR
	var mesh := FlatMesh.new()
	mesh.set_transform(Vector2.ZERO, 0, Vector2(1, 0.55))
	var half := width * 0.54
	var base := PackedVector2Array([Vector2(-half + 18, -92), Vector2(half - 18, -92), Vector2(half, -74), Vector2(half, 40), Vector2(half - 18, 58), Vector2(-half + 18, 58), Vector2(-half, 40), Vector2(-half, -74)])
	mesh.polygon(base, Color("#2a2d31") if not bank else Color("#353332"))
	mesh.line(Vector2(-half + 18, -92), Vector2(half - 18, -92), Color("#727875"), 3)
	mesh.line(Vector2(-half, -72), Vector2(-half, 38), Color("#6a7171"), 3)
	mesh.line(Vector2(-half + 18, 55), Vector2(half - 18, 55), Color("#171c21"), 7)
	for side in [-1, 1]:
		mesh.line(Vector2(side * (half - 16), -75), Vector2(side * (half - 16), 39), Color("#b69961") if bank else Color("#c49753"), 2)
		for y in [-58, -14, 30]:
			mesh.circle(Vector2(side * (half - 8), y), 2.5, Color("#96968b"), 8)
	for i in 5:
		var x := -half + 28 + i * (width / 5)
		mesh.line(Vector2(x, -86), Vector2(x, 49), Color(0.05, 0.07, 0.09, 0.3), 2)
	_mesh = mesh.commit()


func _draw() -> void:
	# Одинаковая геометрия на всех уровнях качества: тень не меняет физику площадки.
	SoftGlow.pool(self, Vector2(52, 24), width * 0.58, 0.36, Color(0.01, 0.02, 0.025, 0.38))
	if _mesh != null:
		draw_mesh(_mesh, null)
	SoftGlow.pool(self, Vector2(0, -22), width * 0.47, 0.30, Color(0, 0, 0, 0.55))
	SoftGlow.pool(self, Vector2(0, 35), width * 0.66, 0.36, Color(tint, 0.21))
