class_name RunShrine
extends Node2D
## Объекты нового Выживания (этап 2): постой рядом — объект срабатывает один раз, Game решает, что дать.
## ALTAR — Мусорный алтарь (вызвать босса раньше, награда выше); VACUUM — Пылесос (собрать весь лут);
## GREED — Касса жадности (+монеты до конца главы, враги крепче); RING — Ринг (волна элиты за награду);
## DEALER — Барыга Шнырь (3 карточки за гайки). Рисунки временные (код); арт Астры — бриф v29,
## assets/world/<kind>.png подхватывается по имени.

signal activated(shrine: RunShrine)

enum Kind { ALTAR, VACUUM, GREED, RING, DEALER }

const NAMES := {Kind.ALTAR: "altar", Kind.VACUUM: "vacuum", Kind.GREED: "greed_register", Kind.RING: "ring", Kind.DEALER: "fence_dealer"}
const TITLES := {Kind.ALTAR: "Алтарь", Kind.VACUUM: "Пылесос", Kind.GREED: "Касса", Kind.RING: "Ринг", Kind.DEALER: "Барыга"}
const HOLD := {Kind.ALTAR: 3.0, Kind.VACUUM: 1.2, Kind.GREED: 2.0, Kind.RING: 2.0, Kind.DEALER: 0.8}
const COLORS := {Kind.ALTAR: "#ff4d4d", Kind.VACUUM: "#6adcff", Kind.GREED: "#ffd23f", Kind.RING: "#ff7a3d", Kind.DEALER: "#b96bff"}
const RADIUS := 95.0
## Высота подписи над объектом (выше рисунка Астры).
const TITLE_Y := {Kind.ALTAR: -150.0, Kind.VACUUM: -100.0, Kind.GREED: -120.0, Kind.RING: -125.0, Kind.DEALER: -165.0}

var kind: Kind = Kind.VACUUM
var player: Node2D
var used := false
var _hold := 0.0
var _cooldown := 0.0
var _time := randf() * 10.0
var _font: Font


func setup(new_kind: Kind) -> void:
	kind = new_kind


func _ready() -> void:
	_font = ThemeDB.fallback_font


func finish() -> void:
	used = true
	set_process(false)
	queue_redraw()


## Не сработал (нет гаек у Барыги, босс уже идёт) — можно попробовать снова через пару секунд.
func refuse() -> void:
	_cooldown = 2.0
	_hold = 0.0


func _process(delta: float) -> void:
	_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	if player == null or not is_instance_valid(player):
		return
	var inside := player.global_position.distance_squared_to(global_position) < RADIUS * RADIUS
	var hold: float = HOLD[kind]
	var before := _hold
	_hold = clampf(_hold + (delta if inside and _cooldown <= 0.0 else -delta * 2.0), 0.0, hold)
	if _hold >= hold:
		_hold = 0.0
		activated.emit(self)
	if before != _hold or int(_time * 8.0) != int((_time - delta) * 8.0):
		queue_redraw()


func _draw() -> void:
	var tint := Color(str(COLORS[kind])) if not used else Color(0.45, 0.45, 0.5)
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 46.0, Color(0, 0, 0, 0.35))
	if not used:
		var pulse := 0.5 + 0.5 * sin(_time * 2.6)
		draw_circle(Vector2.ZERO, RADIUS, Color(tint, 0.07 + 0.05 * pulse))
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 40, Color(tint, 0.55), 3.0)
	draw_set_transform(Vector2.ZERO)
	if not _draw_art():
		_draw_placeholder(tint)
	if used:
		return
	var title: String = TITLES[kind]
	var w := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var ty: float = TITLE_Y[kind]
	draw_string_outline(_font, Vector2(-w * 0.5, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color("#120d1c"))
	draw_string(_font, Vector2(-w * 0.5, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, tint)
	if _hold > 0.0:
		draw_arc(Vector2(0, -50), 60.0, -PI * 0.5, -PI * 0.5 + TAU * _hold / float(HOLD[kind]), 36, tint, 6.0)


## Арт Астры (assets/world/): в покое — статичный рисунок, пока стоишь рядом (или Барыга) — анимация.
func _draw_art() -> bool:
	var dim := Color.WHITE if not used else Color(0.55, 0.55, 0.6)
	var active := _hold > 0.0 and not used
	match kind:
		Kind.ALTAR:
			if active:
				return WorldArt.draw(self, "altar_active", 0.55, int(_time * 8.0) % 6, Vector2(260, 260), 6, dim)
			return WorldArt.draw(self, "altar", 0.55, 0, Vector2.ZERO, 1, dim)
		Kind.VACUUM:
			if active:
				return WorldArt.draw(self, "vacuum_on", 0.8, int(_time * 8.0) % 4, Vector2(200, 200), 4, dim)
			return WorldArt.draw(self, "vacuum", 0.8, 0, Vector2.ZERO, 1, dim)
		Kind.GREED:
			if active:
				return WorldArt.draw(self, "greed_ring", 0.8, int(_time * 8.0) % 4, Vector2(160, 180), 4, dim)
			return WorldArt.draw(self, "greed_register", 0.8, 0, Vector2.ZERO, 1, dim)
		Kind.RING:
			return WorldArt.draw(self, "ring", 0.75, 0, Vector2.ZERO, 1, dim, true)
		Kind.DEALER:
			if active:
				return WorldArt.draw(self, "fence_dealer/offer", 0.58, int(_time * 8.0) % 4, Vector2(256, 256), 4, dim)
			return WorldArt.draw(self, "fence_dealer/idle", 0.58, int(_time * 8.0) % 6, Vector2(256, 256), 4, dim)
	return false


func _draw_placeholder(tint: Color) -> void:
	var dark := Color("#120d1c")
	match kind:
		Kind.ALTAR:
			# Пирамида из телевизоров и экран-глаз.
			for row in 3:
				for i in 3 - row:
					var r := Rect2(-48 + row * 16 + i * 32, -30 - row * 30, 30, 28)
					draw_rect(r.grow(2.0), dark)
					draw_rect(r, Color("#4a4458"))
					draw_rect(r.grow(-5.0), Color(tint, 0.35 + 0.3 * sin(_time * 3.0 + i)))
			draw_circle(Vector2(0, -78), 6.0, tint)
		Kind.VACUUM:
			draw_rect(Rect2(-34, -56, 68, 52).grow(3.0), dark)
			draw_rect(Rect2(-34, -56, 68, 52), Color("#5b7a9e"))
			draw_circle(Vector2(-22, -2), 9.0, dark)
			draw_circle(Vector2(22, -2), 9.0, dark)
			draw_arc(Vector2(34, -70), 26.0, PI * 0.5, PI * 1.5, 12, dark, 11.0)
			draw_arc(Vector2(34, -70), 26.0, PI * 0.5, PI * 1.5, 12, Color("#9aa7b5"), 7.0)
		Kind.GREED:
			draw_rect(Rect2(-32, -60, 64, 58).grow(3.0), dark)
			draw_rect(Rect2(-32, -60, 64, 58), Color("#d9a520"))
			draw_rect(Rect2(-24, -52, 48, 18), Color("#2a2140"))
			for i in 3:
				draw_circle(Vector2(-16 + i * 16, -20), 5.0, dark)
			draw_circle(Vector2(0, -80), 10.0 + 2.0 * sin(_time * 5.0), Color(tint, 0.8))
		Kind.RING:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
			draw_rect(Rect2(-90, -90, 180, 180), Color(0.3, 0.1, 0.1, 0.5))
			draw_rect(Rect2(-90, -90, 180, 180), tint, false, 6.0)
			for c in [Vector2(-90, -90), Vector2(90, -90), Vector2(-90, 90), Vector2(90, 90)]:
				draw_circle(c, 12.0, dark)
			draw_set_transform(Vector2.ZERO)
		Kind.DEALER:
			# Крыса в плаще: силуэт-капля, шляпа, глаза.
			draw_colored_polygon(PackedVector2Array([Vector2(-26, 0), Vector2(26, 0), Vector2(18, -70), Vector2(-18, -70)]), dark)
			draw_colored_polygon(PackedVector2Array([Vector2(-22, -3), Vector2(22, -3), Vector2(15, -66), Vector2(-15, -66)]), Color("#3a2f4f"))
			draw_circle(Vector2(0, -78), 15.0, dark)
			draw_circle(Vector2(0, -78), 12.0, Color("#8a7f9e"))
			draw_rect(Rect2(-20, -98, 40, 8), dark)
			draw_rect(Rect2(-12, -112, 24, 16), dark)
			draw_circle(Vector2(-5, -80), 2.5, tint)
			draw_circle(Vector2(5, -80), 2.5, tint)
