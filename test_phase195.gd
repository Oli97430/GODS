extends SceneTree
## Phase 19.5 — VALIDATION sur le pipeline RÉEL (galaxie -> systèmes -> planètes -> lunes) :
##   1) DÉTERMINISME : deux générations de la même galaxie => noms système/planète/lune identiques.
##   2) RÉGIONALISATION : les systèmes spatialement proches partagent majoritairement leur palette.
##   3) ÉCHANTILLON lisible : on imprime quelques systèmes avec leurs planètes et lunes (revue du TON).
## Lancement : ...console.exe --headless --path <proj> -s res://test_phase195.gd

func _initialize() -> void:
	var gseed := 20260531
	var radius := 50.0
	var count := 80

	# Génération complète, deux fois (pour comparer => déterminisme).
	var g1 = GalaxyGenerator.generate(gseed, count, radius)
	var g2 = GalaxyGenerator.generate(gseed, count, radius)

	# --- 1) DÉTERMINISME : système + palette + planètes + lunes identiques sur 2 runs ---
	var det_ok := true
	for i in g1.systems.size():
		var s1 = g1.systems[i]
		var s2 = g2.systems[i]
		if s1.name != s2.name or s1.palette_id != s2.palette_id:
			det_ok = false
			break
		var d1 = SystemGenerator.generate(s1.seed_local, s1.star_type, s1.palette_id, s1.name)
		var d2 = SystemGenerator.generate(s2.seed_local, s2.star_type, s2.palette_id, s2.name)
		if d1.planets.size() != d2.planets.size():
			det_ok = false
			break
		for j in d1.planets.size():
			if d1.planets[j].name != d2.planets[j].name:
				det_ok = false
				break
			var m1 = d1.planets[j].moons
			var m2 = d2.planets[j].moons
			for k in m1.size():
				if m1[k].name != m2[k].name:
					det_ok = false
					break
	print("===== PHASE 19.5 — VALIDATION =====")
	print("DÉTERMINISME (noms identiques sur 2 générations) : %s" % str(det_ok))

	# --- 2) RÉGIONALISATION : part moyenne des 5 plus proches voisins partageant la palette ---
	var n := int(g1.systems.size())
	var total := 0.0
	for i in n:
		var si = g1.systems[i]
		var nbrs := []
		for j in n:
			if j == i:
				continue
			nbrs.append({"d": si.position.distance_to(g1.systems[j].position), "p": g1.systems[j].palette_id})
		nbrs.sort_custom(func(a, b): return a.d < b.d)
		var kk := mini(5, nbrs.size())
		var same := 0
		for t in kk:
			if nbrs[t].p == si.palette_id:
				same += 1
		total += float(same) / float(kk)
	var baseline := int(round(100.0 / float(NameGenerator.PALETTES.size())))
	print("RÉGIONALISATION (5 plus proches voisins de même palette) : %.0f%%  (hasard ≈ %d%%)" % [total / float(n) * 100.0, baseline])

	# --- 2b) ÉQUILIBRE : distribution des palettes sur toute la galaxie (contraste préservé ?) ---
	var hist := {}
	for i in NameGenerator.PALETTES.size():
		hist[i] = 0
	for s in g1.systems:
		hist[s.palette_id] += 1
	var hline := ""
	for i in NameGenerator.PALETTES.size():
		hline += "%s:%d  " % [NameGenerator.palette_name(i), hist[i]]
	print("DISTRIBUTION palettes (sur %d systèmes) : %s" % [n, hline])

	# --- 3) ÉCHANTILLON lisible : 8 systèmes, planètes + lunes (revue du TON contemplatif) ---
	print("\n----- ÉCHANTILLON (8 systèmes) -----")
	for i in mini(8, n):
		var s = g1.systems[i]
		var d = SystemGenerator.generate(s.seed_local, s.star_type, s.palette_id, s.name)
		print("◆ %s  [%s]  — %d planète(s)" % [s.name, NameGenerator.palette_name(s.palette_id), d.planets.size()])
		for p in d.planets:
			var moons := ""
			for m in p.moons:
				moons += "   · " + m.name
			print("    – %s%s" % [p.name, moons])
	quit()
