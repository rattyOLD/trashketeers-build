class_name BattleMemory
extends RefCounted
## Видеопамять между режимами: всё, что бой подгрузил (кадры врагов, риги, пропсы, живность, эффекты
## оружия), держится в статических кэшах. Без очистки выживание → меню → сюжет складывает текстуры
## обоих режимов, и iPhone (Safari) убивает вкладку по памяти. Вызывается при выходе из боя в меню;
## следующий бой подгрузит нужное заново (и прогреет главу заранее).


static func release() -> void:
	FrameDB.release_textures()
	RigDB.release_textures()
	ArenaProp._textures.clear()
	AmbientLife._frames.clear()
	AmbientLife._textures.clear()
	WeaponVfx._sheets.clear()
	WeaponVfx._atlas.clear()
	ContentDB._texture_cache.clear()
	Cosmetics._skin_tex.clear()
	for id in ContentDB.get_enemy_ids():
		var data := ContentDB.get_enemy(id)
		if data != null:
			data.release_textures()
