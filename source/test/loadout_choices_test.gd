extends Node2D
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("LOADOUT_CHOICES: " + label)

func _ready() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.add_weapon(&"smg_v1", 1, false)
	SaveService.set_secondary_weapon(&"smg_v1", 1)
	_check(SaveService.get_secondary_loadout().id == &"smg_v1", "owned secondary weapon selected")
	_check(LoadoutPresets.capture(0), "kit captured")
	SaveService.data["secondary_weapon"] = ""
	_check(LoadoutPresets.apply(0) and SaveService.get_secondary_loadout().id == &"smg_v1", "kit restores both weapon slots")
	var before := SaveService.data.duplicate(true)
	var forged := LoadoutPresets.get_preset(0)
	forged["hero"] = "unknown"
	SaveService.data["loadout_presets"][1] = forged
	_check(not LoadoutPresets.apply(1) and SaveService.data["character"] == before["character"], "invalid kit cannot grant a hero or partially apply")
	forged = LoadoutPresets.get_preset(0)
	forged["primary_tier"] = 5
	_check(not LoadoutPresets.error_for(forged).is_empty(), "unowned tier rejected")
	forged["primary_tier"] = "bad"
	_check(not LoadoutPresets.error_for(forged).is_empty(), "malformed tier rejected")
	forged = LoadoutPresets.get_preset(0)
	forged["patches"] = ["forged_patch"]
	_check(not LoadoutPresets.error_for(forged).is_empty(), "unknown patch rejected")
	_check(not LoadoutPresets.capture(3), "only three kits")
	for meta in [true, false]:
		var battle := BattleBase.new()
		add_child(battle)
		battle.meta_enabled = meta
		battle._build_layers()
		battle._spawn_player(Vector2.ZERO, SaveService.get_loadout(), func(_at: Vector2, _range: float) -> Node2D: return null)
		_check((battle.player.weapon_controller.slots[1] != null) == meta, "secondary respects story loadout gating")
		battle.free()
	var boss := Enemy.new()
	add_child(boss)
	boss.activate(ContentDB.get_enemy(&"beer_baron"), Vector2.ZERO)
	var cover := BossCover.new()
	add_child(cover)
	var barrels: Array[DestructibleObject] = []
	for i in 5:
		var barrel := DestructibleObject.new()
		add_child(barrel)
		barrel.setup_art("d_barrel", self)
		barrel.position = Vector2(80 + i * 90, 0)
		barrels.append(barrel)
	_check(cover.attach(boss, barrels) == 3, "bounded three marked existing barrels")
	barrels[0].take_damage(999.0)
	_check(cover.interruptions == 1 and boss.posture_stun >= 0.9, "nearby broken cover opens a real boss attack window")
	boss.posture_stun = 0.0
	boss.position = Vector2(-1000, 0)
	barrels[1].take_damage(999.0)
	_check(cover.interruptions == 1 and boss.posture_stun == 0.0, "distant destruction does not interrupt boss")
	cover.clear()
	_check(not barrels[2].destroyed.is_connected(cover._broken), "chapter cleanup releases cover signals")
	cover.free()
	boss.free()
	for barrel in barrels:
		barrel.free()
	for character: Dictionary in CharacterDB.all():
		if not HeroIdentity.HEADS.has(str(character.get("id", ""))):
			continue
		var preview := MenuWidgets.RaccoonPreview.new({}, 1.0, character)
		add_child(preview)
		preview.set_motion("run")
		for frame in 60:
			preview._process(1.0 / 60.0)
		_check(preview.raccoon._clip_cur == "run", str(character["id"]) + " shows running preview")
		preview.set_motion("shoot")
		for frame in 60:
			preview._process(1.0 / 60.0)
		_check(preview.raccoon._clip_cur == "shoot", str(character["id"]) + " shows shooting preview")
		preview.set_motion("ready")
		for frame in 60:
			preview._process(1.0 / 60.0)
		_check(not preview.raccoon.aiming and preview.raccoon._action == "ready", str(character["id"]) + " shows weapon preparation")
		preview.free()
	var popup := LoadoutPopup.new()
	add_child(popup)
	popup.open()
	await get_tree().create_timer(0.3).timeout
	_check(popup._list.get_child_count() >= 4, "all three saved kit cards visible")
	popup.free()
	print("LOADOUT_CHOICES failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
