extends Node
## Попиксельное сравнение: штатные draw_* против PolyBatch.

class Native:
	extends Node2D
	var batched := false
	func _draw() -> void:
		var b := PolyBatch.new()
		var outline := LiquidDraw.outline(5)
		for k in 6:
			var at := Vector2(60 + k * 70, 60)
			var col := Color(0.2 + k * 0.1, 0.8, 0.4, 0.35 + k * 0.08)
			if batched:
				b.circle(at, 10.0 + k * 4.0, col)
				b.circle(at + Vector2(6, 4), 8.0, Color(col, 0.5))
			else:
				draw_circle(at, 10.0 + k * 4.0, col)
				draw_circle(at + Vector2(6, 4), 8.0, Color(col, 0.5))
		for k in 4:
			var at := Vector2(70 + k * 100, 160)
			var rot := 0.4 * k
			var sc := Vector2(1.0, 0.55)
			if batched:
				b.set_transform(at, rot, sc)
				b.circle(Vector2.ZERO, 34.0, Color(0.1, 0.05, 0.2, 0.6))
				b.circle(Vector2(8, -4), 20.0, Color(0.9, 0.3, 0.6, 0.3))
				b.arc(Vector2.ZERO, 27.0, -2.3, -1.0, 16, Color(0.7, 0.55, 0.95, 0.4), 4.0, true)
				b.reset_transform()
			else:
				draw_set_transform(at, rot, sc)
				draw_circle(Vector2.ZERO, 34.0, Color(0.1, 0.05, 0.2, 0.6))
				draw_circle(Vector2(8, -4), 20.0, Color(0.9, 0.3, 0.6, 0.3))
				draw_arc(Vector2.ZERO, 27.0, -2.3, -1.0, 16, Color(0.7, 0.55, 0.95, 0.4), 4.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for k in 3:
			var at := Vector2(90 + k * 140, 270)
			var r := 50.0 - k * 8.0
			var pts := PackedVector2Array()
			for p in outline:
				pts.append(at + p * r)
			var edge := pts.duplicate()
			edge.append(edge[0])
			if batched:
				b.polygon_cached(5, outline, r * 1.07, at, Color(0.3, 0.6, 0.1, 0.6))
				b.polygon(pts, Color(0.5, 0.9, 0.2, 0.7))
				b.polyline(edge, Color(1, 1, 1, 0.8), 3.0, true)
				b.arc(at, r * 0.6, 0.0, TAU, 24, Color(1, 1, 1, 0.3), 2.0, true)
				b.arc(at + Vector2(-10, -6), 9.0, 0.0, TAU, 10, Color(1, 1, 1, 0.55), 1.5, true)
			else:
				draw_colored_polygon(_sc(outline, at, r * 1.07), Color(0.3, 0.6, 0.1, 0.6))
				draw_colored_polygon(pts, Color(0.5, 0.9, 0.2, 0.7))
				draw_polyline(edge, Color(1, 1, 1, 0.8), 3.0, true)
				draw_arc(at, r * 0.6, 0.0, TAU, 24, Color(1, 1, 1, 0.3), 2.0, true)
				draw_arc(at + Vector2(-10, -6), 9.0, 0.0, TAU, 10, Color(1, 1, 1, 0.55), 1.5, true)
		var zig := PackedVector2Array([Vector2(20, 360), Vector2(80, 330), Vector2(80, 330), Vector2(140, 380), Vector2(200, 340), Vector2(205, 341)])
		for k in 2:
			var pts2 := Transform2D(0, Vector2(k * 230, 0)) * zig
			if batched:
				b.polyline(pts2, Color(1, 0.5, 0.2, 0.7), 5.0, k == 1)
				b.line(Vector2(20 + k * 230, 400), Vector2(200 + k * 230, 430), Color(0.2, 0.9, 1, 0.6), 4.0)
				b.polyline(PackedVector2Array([Vector2(30 + k * 230, 440), Vector2(60 + k * 230, 420), Vector2(90 + k * 230, 440)]), Color(1, 1, 0, 0.5), 0.6, true)
			else:
				draw_polyline(pts2, Color(1, 0.5, 0.2, 0.7), 5.0, k == 1)
				draw_line(Vector2(20 + k * 230, 400), Vector2(200 + k * 230, 430), Color(0.2, 0.9, 1, 0.6), 4.0)
				draw_polyline(PackedVector2Array([Vector2(30 + k * 230, 440), Vector2(60 + k * 230, 420), Vector2(90 + k * 230, 440)]), Color(1, 1, 0, 0.5), 0.6, true)
		for k in 3:
			var r := Rect2(250 + k * 70, 440, 50 + k * 3.5, 22.3)
			if batched:
				b.rect(r, Color(0.9, 0.6, 0.1, 0.5 + k * 0.2))
				b.rect(Rect2(r.position + Vector2(3, 3), Vector2(10.5, 7.25)), Color("#e8b41a"))
				b.circle(r.position + Vector2(30, 10), 2.5, Color("#4a4e68"))
			else:
				draw_rect(r, Color(0.9, 0.6, 0.1, 0.5 + k * 0.2))
				draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(10.5, 7.25)), Color("#e8b41a"))
				draw_circle(r.position + Vector2(30, 10), 2.5, Color("#4a4e68"))
		if batched:
			b.flush(self)

	func _sc(p: PackedVector2Array, at: Vector2, r: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for v in p:
			out.append(at + v * r)
		return out


func _ready() -> void:
	PolyBatch.exact = true
	var imgs: Array[Image] = []
	var draws: Array[int] = []
	for batched in [false, true]:
		var vp := SubViewport.new()
		vp.size = Vector2i(480, 470)
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var bg := ColorRect.new()
		bg.color = Color(0.13, 0.1, 0.17)
		bg.size = Vector2(480, 470)
		vp.add_child(bg)
		var n := Native.new()
		n.batched = batched
		vp.add_child(n)
		for i in 4:
			await RenderingServer.frame_post_draw
		imgs.append(vp.get_texture().get_image())
		vp.queue_free()
		await RenderingServer.frame_post_draw
	var a := imgs[0]
	var b := imgs[1]
	var diff_px := 0
	var max_d := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
			if d > 0.0:
				diff_px += 1
				max_d = maxf(max_d, d)
	a.save_png(OS.get_environment("OUT") + "/pb_native.png")
	b.save_png(OS.get_environment("OUT") + "/pb_batched.png")
	print("PBTEST pixels_different=%d of %d  max_channel_diff=%.4f (%.1f/255)" % [diff_px, a.get_width() * a.get_height(), max_d, max_d * 255.0])
	get_tree().quit()
