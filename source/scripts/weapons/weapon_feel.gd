class_name WeaponFeel
extends RefCounted
## Различия отдачи и вспышек используют существующие эффекты и общий бюджет.

static func automatic(w: WeaponData) -> bool:
	return w.icon in [&"smg", &"rifle", &"lmg", &"minigun"]


static func heavy(w: WeaponData) -> bool:
	return w.icon in [&"shotgun", &"pump", &"double", &"launcher", &"mortar"]


static func precision(w: WeaponData) -> bool:
	return w.icon in [&"sniper", &"rail", &"railgun"]


static func recovery(w: WeaponData) -> float:
	return 24.0 if automatic(w) else (9.0 if heavy(w) else (11.0 if precision(w) else 14.0))


static func flash_scale(w: WeaponData) -> float:
	return 0.65 if automatic(w) else (1.15 if heavy(w) else (1.25 if precision(w) else 1.0))


static func flash_time(w: WeaponData) -> float:
	return 0.05 if automatic(w) else (0.11 if precision(w) else 0.085)


static func camera_scale(w: WeaponData) -> float:
	return 0.55 if automatic(w) else (1.15 if precision(w) else 1.0)


static func sound_pitch(w: WeaponData) -> float:
	return randf_range(0.9, 0.96) if heavy(w) else randf_range(0.98, 1.02)
