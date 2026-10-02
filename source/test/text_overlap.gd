class_name TextOverlap
extends RefCounted
## Ищет подписи, которые налезают друг на друга. Берёт видимые Label, RichTextLabel и Button с текстом,
## считает реальный прямоугольник текста (не всей рамки) и сравнивает попарно.

static func collect(root: Node, out: Array = []) -> Array:
	if root is CanvasItem and not (root as CanvasItem).visible:
		return out
	if root is Control:
		var c := root as Control
		if c.modulate.a < 0.2 or c.self_modulate.a < 0.05:
			return out
		var text := ""
		if c is Label:
			text = (c as Label).text
		elif c is RichTextLabel:
			text = (c as RichTextLabel).get_parsed_text()
		elif c is Button:
			text = (c as Button).text
		if text.strip_edges() != "" and c.size.x > 4.0 and c.size.y > 4.0 and c.is_visible_in_tree():
			var rect := _clip_to_ancestors(c, _text_rect(c, text))
			if rect.size.x > 2.0 and rect.size.y > 2.0:
				out.append({"node": c, "text": text.strip_edges(), "rect": rect})
	for child in root.get_children():
		collect(child, out)
	return out


## Всё, что вылезло за прокрутку или обрезку родителя, пользователь не видит: не считаем.
static func _clip_to_ancestors(c: Control, rect: Rect2) -> Rect2:
	var p := c.get_parent()
	var alpha := 1.0
	while p != null:
		if p is Control:
			var pc := p as Control
			alpha *= pc.modulate.a
			if pc is ScrollContainer or pc.clip_contents:
				rect = rect.intersection(pc.get_global_rect())
				if rect.size.x <= 0.0 or rect.size.y <= 0.0:
					return Rect2()
		p = p.get_parent()
	return rect if alpha > 0.2 else Rect2()


static func _text_rect(c: Control, text: String) -> Rect2:
	var r := c.get_global_rect()
	var font: Font = c.get_theme_font("font")
	var fs := c.get_theme_font_size("font_size")
	if c is RichTextLabel:
		font = c.get_theme_font("normal_font")
		fs = c.get_theme_font_size("normal_font_size")
	if font == null:
		return r
	var wrapped := (c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF) or c is RichTextLabel
	if wrapped:
		return r
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h := font.get_height(fs)
	var align := HORIZONTAL_ALIGNMENT_CENTER
	if c is Label:
		align = (c as Label).horizontal_alignment
	elif c is Button:
		align = (c as Button).alignment as HorizontalAlignment
	var x := r.position.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x = r.position.x + (r.size.x - w) * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x = r.end.x - w
	var y := r.position.y + (r.size.y - h) * 0.5
	if w > r.size.x:
		# Текст шире рамки: обрезается или вылезает, считаем по рамке.
		x = r.position.x
		w = r.size.x
	return Rect2(x, y, w, h)


static func find(root: Node, min_overlap: float = 6.0) -> Array:
	var items := collect(root)
	var out: Array = []
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			var na: Node = a["node"]
			var nb: Node = b["node"]
			if na.is_ancestor_of(nb) or nb.is_ancestor_of(na):
				continue
			var inter: Rect2 = (a["rect"] as Rect2).intersection(b["rect"])
			if inter.size.x > min_overlap and inter.size.y > min_overlap:
				out.append("«%s» × «%s» %s" % [str(a["text"]).left(28), str(b["text"]).left(28), str(inter.size.snapped(Vector2.ONE))])
	return out
