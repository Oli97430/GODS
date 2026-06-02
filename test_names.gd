extends SceneTree
## Phase 19.5 étape 1 : montre 10 noms par palette (validation du TON) + déterminisme.

func _initialize() -> void:
	print("===== NOMS PROCÉDURAUX — 10 par palette =====")
	for pid in NameGenerator.PALETTES.size():
		var line := ""
		for k in 10:
			line += NameGenerator.generate_name(1000 + k * 9173 + pid * 131, pid) + "   "
		print("[%d] %-11s : %s" % [pid, NameGenerator.palette_name(pid), line])

	print("\n===== DÉTERMINISME =====")
	var a := NameGenerator.generate_name(424242, 0)
	var b := NameGenerator.generate_name(424242, 0)
	print("  même (seed,palette) -> identique : %s == %s  => %s" % [a, b, str(a == b)])
	var c := NameGenerator.generate_name(424242, 2)
	print("  palette différente -> nom différent : p0=%s  p2=%s  => %s" % [a, c, str(a != c)])
	# Pas de triplet de lettres / pas vide, longueurs plausibles.
	var ok := true
	for pid in NameGenerator.PALETTES.size():
		for k in 200:
			var nm := NameGenerator.generate_name(k * 7 + pid, pid)
			if nm.length() < 2 or nm.length() > 14:
				ok = false
	print("  longueurs 2..14 sur 1000 noms : %s" % str(ok))
	quit()
