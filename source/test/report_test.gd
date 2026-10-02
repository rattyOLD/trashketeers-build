extends Node
## Проверка тела отчёта о забеге: гости/тестовые игроки пропускаются, поля приведены к числам, run_id похож на UUID v4.

func _ready() -> void:
	var fails := 0
	var results := {"waves_cleared": 5, "seconds": 140, "won": true, "players": {
		2: {"kills": 10, "damage": 900, "revives": 1, "downs": 0, "left": false, "coins": 120, "xp": 40},
		3: {"kills": 4, "damage": 300, "revives": 0, "downs": 2, "left": true, "coins": 0, "xp": 0},
		4: {"kills": 1}}}
	var body := CoopNet.build_report("rid", results, {2: "uid-a", 3: "uid-b", 4: "test:x"})
	if (body["players"] as Array).size() != 2:
		fails += 1
		print("FAIL players count ", body["players"])
	if int(body["waves"]) != 5 or not bool(body["won"]):
		fails += 1
		print("FAIL head ", body)
	var left_ok := false
	for p: Variant in body["players"]:
		if str((p as Dictionary)["uid"]) == "uid-b" and bool((p as Dictionary)["left"]):
			left_ok = true
	if not left_ok:
		fails += 1
		print("FAIL left flag")
	var id := CoopNet.new_run_id()
	var re := RegEx.new()
	re.compile("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	if re.search(id) == null or id == CoopNet.new_run_id():
		fails += 1
		print("FAIL run_id ", id)
	print("REPORT_TEST ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(fails)
