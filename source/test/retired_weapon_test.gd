extends Node
func _ready() -> void:
	SaveService.data["arsenal"] = {"rail_needle_v1": [1, 1, 0, 0, 0], "pistol_v1": [1, 0, 0, 0, 0]}
	SaveService.data["selected_weapon"] = "rail_needle_v1"
	var before := int(SaveService.data["nuts"])
	SaveService._refund_retired_weapons()
	SaveService._sanitize_arsenal()
	var gain := int(SaveService.data["nuts"]) - before
	var ok := gain == 3 * 1000 and not (SaveService.data["arsenal"] as Dictionary).has("rail_needle_v1") and str(SaveService.data["selected_weapon"]) == str(SaveService.START_WEAPON)
	print("RETIRED_TEST ", "PASS" if ok else "FAIL gain=%d" % gain)
	get_tree().quit()
