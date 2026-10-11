class_name ArtDirection
extends RefCounted
## Палитры материалов: холодная полутень, тёплые грани, узнаваемые цвета группировок.
const FACTIONS := {
	"scrap": [Vector3(0.82, 0.91, 0.96), Vector3(1.10, 1.01, 0.86), Color("#bc714d")],
	"bank": [Vector3(0.86, 0.91, 1.00), Vector3(1.08, 1.04, 0.87), Color("#c8ab60")],
	"bureau": [Vector3(0.78, 0.91, 1.08), Vector3(0.97, 1.03, 1.05), Color("#77a2b8")],
	"toxic": [Vector3(0.83, 1.02, 0.89), Vector3(1.06, 1.06, 0.85), Color("#a4b965")],
	"roofs": [Vector3(0.83, 0.91, 1.08), Vector3(1.06, 0.98, 0.90), Color("#9caabd")],
}
const CLOTHES := {
	"scrap": ["#392820", "#795340", "#b99b76", 0.55],
	"bank": ["#252d38", "#53616b", "#aaa88e", 0.55],
	"bureau": ["#141f2b", "#3a5363", "#778e9a", 0.65],
	"toxic": ["#253623", "#536743", "#a3af70", 0.55],
	"roofs": ["#242c3e", "#535972", "#9794a6", 0.55],
}
static var _materials: Dictionary = {}


static func faction(id: String) -> String:
	if id.begins_with("fed_"):
		return "bureau"
	if "toxic" in id or "acid" in id or id == "bomb_rat":
		return "toxic"
	if "pigeon" in id:
		return "roofs"
	if "pig" in id or "vault" in id or id in ["mud_magnate", "cash_collector", "croupier", "chef_boss"]:
		return "bank"
	return "scrap"


static func apply(material: ShaderMaterial, family: String = "scrap", strength: float = 0.24) -> void:
	var colors: Array = FACTIONS.get(family, FACTIONS["scrap"])
	material.set_shader_parameter("paint_strength", strength)
	material.set_shader_parameter("paint_shadow", colors[0])
	material.set_shader_parameter("paint_light", colors[1])
	material.set_shader_parameter("paint_saturation", 0.84)


static func material(family: String = "scrap", strength: float = 0.24) -> ShaderMaterial:
	var key := "%s:%.3f" % [family, strength]
	if _materials.has(key):
		return _materials[key]
	var result := ShaderMaterial.new()
	result.shader = load("res://shaders/painted_world.gdshader")
	apply(result, family, strength)
	_materials[key] = result
	return result
