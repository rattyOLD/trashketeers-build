class_name HeroIdentity
extends RefCounted
## Portraits reuse the original face pixels. Outfits never recolor the face.
## These regions refer to frame zero of each character's canonical idle sheet.
const HEADS := {
	"raccoon": Rect2i(118, 16, 96, 74),
	"maloy": Rect2i(118, 16, 120, 98),
	"red_panda": Rect2i(145, 16, 68, 60),
	"snow": Rect2i(119, 14, 70, 55),
	"night": Rect2i(128, 16, 74, 62),
	"neon_hopper": Rect2i(99, 6, 93, 70),
	"fluffy_chemist": Rect2i(112, 10, 103, 83),
	"pigeon_mafioso": Rect2i(121, 3, 88, 83),
	"sniper_f": Rect2i(129, 12, 76, 68),
	"medic_f": Rect2i(123, 14, 88, 66),
}
static var _portraits: Dictionary = {}

static func portrait(character: Dictionary) -> ImageTexture:
	var id := str(character.get("id", ""))
	if _portraits.has(id):
		return _portraits[id]
	if not HEADS.has(id):
		return null
	var path := str((character.get("sprite", {}) as Dictionary).get("clips", "")) + "idle.png"
	if not ResourceLoader.exists(path):
		return null
	var source := (load(path) as Texture2D).get_image()
	if source.is_compressed():
		source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var region: Rect2i = HEADS[id]
	# Padding keeps ears and headgear inside circular avatar frames.
	var side := ceili(maxi(region.size.x, region.size.y) * 1.2)
	var face := Image.create(side, side, false, Image.FORMAT_RGBA8)
	face.fill(Color.TRANSPARENT)
	face.blit_rect(source, region, (Vector2i(side, side) - region.size) / 2)
	var texture := ImageTexture.create_from_image(face)
	_portraits[id] = texture
	return texture
