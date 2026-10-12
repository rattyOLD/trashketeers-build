class_name LoadoutPresets
extends RefCounted
const COUNT := 3

static func get_preset(slot: int) -> Dictionary:
	var presets: Array = SaveService.data.get("loadout_presets", [])
	if slot < 0 or slot >= COUNT or slot >= presets.size() or not presets[slot] is Dictionary:
		return {}
	return presets[slot].duplicate(true)

static func capture(slot: int) -> bool:
	if slot < 0 or slot >= COUNT:
		return false
	var presets: Array = SaveService.data.get("loadout_presets", []).duplicate(true)
	presets.resize(COUNT)
	var secondary := SaveService.get_secondary_loadout()
	presets[slot] = {"hero": SaveService.get_character_id(), "skin": SaveService.get_selected_skin(),
		"primary": String(SaveService.get_selected_weapon()), "primary_tier": SaveService.get_loadout().tier,
		"secondary": String(secondary.id) if secondary != null else "", "secondary_tier": secondary.tier if secondary != null else 1,
		"patches": Patches.worn()}
	SaveService.data["loadout_presets"] = presets
	SaveService.save_data()
	return true

static func error_for(kit: Dictionary) -> String:
	if kit.is_empty():
		return "Комплект ещё не сохранён"
	var hero := str(kit.get("hero", ""))
	if not CharacterDB.has_character(hero) or not SaveService.owns_character(hero) or SaveService.hero_fallen(hero):
		return "Герой сейчас недоступен"
	if not SaveService.SKINS.has(str(kit.get("skin", ""))) or not SaveService.owns_skin(str(kit.get("skin", ""))):
		return "Наряд недоступен"
	for part in ["primary", "secondary"]:
		var id := StringName(str(kit.get(part, "")))
		if part == "secondary" and id == &"":
			continue
		if not WeaponDB.has_weapon(id) or not SaveService.owns_weapon(id):
			return "Оружие из комплекта недоступно"
		var raw: Variant = kit.get(part + "_tier", 1)
		if not ConfigLoader.type_matches(raw, 0) or int(raw) < 1 or int(raw) > WeaponData.MAX_TIER or SaveService.get_copies(id, int(raw)) <= 0:
			return "Тир оружия изменился — пересохрани комплект"
	if str(kit.get("primary", "")) == str(kit.get("secondary", "")):
		return "Для второго слота выбери другой ствол"
	var patches: Variant = kit.get("patches", [])
	if not patches is Array or patches.size() > Patches.open_slots():
		return "Недоступны слоты нашивок"
	var seen := {}
	for patch: Variant in patches:
		if not patch is String or not Patches.CATALOG.has(patch) or Patches.level(patch) <= 0 or seen.has(patch):
			return "Нашивка недоступна"
		seen[patch] = true
	return ""

static func apply(slot: int) -> bool:
	var kit := get_preset(slot)
	if not error_for(kit).is_empty():
		return false
	# Validate the entire snapshot before mutating anything. No unlocks or gifts.
	SaveService.data["character"] = kit["hero"]
	SaveService.data["selected_skin"] = kit["skin"]
	SaveService.data["selected_weapon"] = kit["primary"]
	SaveService.data["selected_tier"] = kit["primary_tier"]
	SaveService.data["secondary_weapon"] = kit["secondary"]
	SaveService.data["secondary_tier"] = kit["secondary_tier"]
	SaveService.data["patch_worn"] = kit["patches"].duplicate()
	SaveService.save_data()
	return true
