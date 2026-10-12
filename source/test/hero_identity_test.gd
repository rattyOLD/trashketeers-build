extends Node
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("HERO_IDENTITY: " + label)

func _ready() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	for character: Dictionary in CharacterDB.all():
		var id := str(character["id"])
		if not HeroIdentity.HEADS.has(id):
			continue
		var portrait := HeroIdentity.portrait(character)
		_check(portrait != null, id + " has canonical face")
		if portrait == null:
			continue
		var path := str(character["sprite"]["clips"]) + "idle.png"
		var source := (load(path) as Texture2D).get_image()
		if source.is_compressed():
			source.decompress()
		var rect: Rect2i = HeroIdentity.HEADS[id]
		var image := portrait.get_image()
		var offset := (image.get_size() - rect.size) / 2
		var same := true
		for y in rect.size.y:
			for x in rect.size.x:
				if source.get_pixelv(rect.position + Vector2i(x, y)) != image.get_pixelv(offset + Vector2i(x, y)):
					same = false
		_check(same, id + " preserves every original face pixel")
		_check(MenuWidgets.Avatar.get_texture_for(character, "classic") == portrait, id + " menu shares canonical face")
		_check(MenuWidgets.Avatar.get_texture_for(character, "neon") == portrait, id + " outfit does not change the face")
		_check(ChatPopup.PeerAvatar.portrait_of(id) == portrait, id + " chat shares canonical face")
		_check(AvatarPicker.portrait_texture("res://assets/ui/portraits/avatar/" + id + ".png") == portrait, id + " built-in avatar shares canonical face")
		var hud := HudWidgets.DamagePortrait.new()
		add_child(hud)
		hud.set_character(character)
		for hp in [1.0, 0.6, 0.3, 0.1]:
			hud.set_health(hp)
			hud.react("hit")
			_check(hud._face.tex == portrait, id + " health and reactions preserve identity")
		hud.free()
		var result := HeroMoodCard.new(character, true)
		result._character = character
		_check(result._pick_texture(id, true) == portrait and result._pick_texture(id, false) == portrait, id + " both results share canonical face")
		result.free()
	_check(HeroIdentity._portraits.size() == 10, "bounded ten small portraits")
	print("HERO_IDENTITY failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
