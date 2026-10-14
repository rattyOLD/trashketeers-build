extends Node

var draws := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var visual := RaccoonVisual.new()
	add_child(visual)
	visual.position = Vector2(300, 300)
	visual._front_layer.draw.connect(func() -> void:
		draws += 1
		# This exact subpixel star failed canvas_item_add_polygon before the fix.
		visual._draw_star(Vector2(39.99526, -7.136974), 0.0026, Color.WHITE)
		for radius in [0.0, 0.000001, 0.003, 0.0031, 0.01, 0.1, 0.249, 0.25, 1.0, 6.0]:
			visual._draw_star(Vector2(50, -20), radius, Color.WHITE)
	)
	visual._front_layer.queue_redraw()
	for frame in 8: await get_tree().process_frame
	visual.free()
	for frame in 4: await get_tree().process_frame
	var failures := int(draws == 0)
	print("DEATH_GEOMETRY draws=", draws)
	print("DEATH_GEOMETRY failures=", failures)
	get_tree().quit(failures)
