class_name DevicePerformance
extends RefCounted

## Android сообщает SM-A135F/DS, SM-A137F или SM-A136U вместо торгового имени.
static func is_galaxy_a13(model: String) -> bool:
	var name := model.strip_edges().to_upper()
	for prefix in ["SM-A135", "SM-A137", "SM-A136"]:
		if name.begins_with(prefix):
			return true
	return name in ["GALAXY A13", "SAMSUNG GALAXY A13"] or name.begins_with("SAMSUNG GALAXY A13 ")


static func native_render_scale(cap: float) -> float:
	return clampf(cap / 1.5, 0.75, 1.0)


## 30 FPS, выбранные игроком или профилем телефона, не являются просадкой.
static func adapt_threshold(target_fps: int, late_stage: bool) -> float:
	return minf(26.0 if late_stage else 38.0, float(target_fps) * 0.8)
