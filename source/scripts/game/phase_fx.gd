class_name PhaseFx
extends RefCounted
## Эффекты второй фазы (Астра, бриф v28: assets/vfx/phase2/): летящий серп, разрез рывка катаны,
## ударная волна молота, разделение выстрела, перегрев, значок «Фаза 2». Ленивые текстуры с кэшем.

const DIR := "res://assets/vfx/phase2/"
static var _tex := {}
static var _frames := {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := DIR + name + ".png"
		_tex[name] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tex[name]


## Один кадр листа (для пули-снаряда, которая не умеет листать кадры).
static func frame(name: String, index: int, cell: Vector2) -> Texture2D:
	var key := "%s:%d" % [name, index]
	if not _frames.has(key):
		var t := tex(name)
		if t == null:
			return null
		var atlas := AtlasTexture.new()
		atlas.atlas = t
		atlas.region = Rect2(Vector2(index * cell.x, 0), cell)
		_frames[key] = atlas
	return _frames[key]
