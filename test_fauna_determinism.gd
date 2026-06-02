extends SceneTree
## Déterminisme (exigence forte du brief) : même seed -> même roster ET même placement ; seeds
## différents -> rosters différents. Appels purs (statiques), pas besoin de l'arbre de scène.

func _initialize() -> void:
	var ok := true
	var lib := FaunaLibrary.new()

	# Roster : reproductible par seed, variable selon le seed.
	var r1 := PlanetFaunaRoster.generate(54321, lib)
	var r2 := PlanetFaunaRoster.generate(54321, lib)
	ok = _chk("roster reproductible (même seed)", _same_roster(r1, r2)) and ok
	var r3 := PlanetFaunaRoster.generate(99999, lib)
	ok = _chk("roster varie selon le seed", not _same_roster(r1, r3)) and ok

	# Placement d'un chunk : reproductible à l'identique (mêmes args).
	var ad := Vector3.UP
	var e := Vector3.RIGHT
	var n := Vector3.FORWARD
	var pr := SurfaceGenerator.DEFAULT_PLANET_PHYS_RADIUS
	var vs := SurfaceGenerator.DEFAULT_VERTICAL_SCALE
	var cs := 32.0
	var a := ChunkFauna.seed_chunk(54321, 3, -2, r1, ad, e, n, cs, pr, vs)
	var b := ChunkFauna.seed_chunk(54321, 3, -2, r1, ad, e, n, cs, pr, vs)
	ok = _chk("placement reproductible (même chunk)", _same_spawns(a, b)) and ok
	# Préférence douce : terre ferme jamais totalement vide (au moins un chunk peuplé sur un échantillon).
	var any := false
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			if not ChunkFauna.seed_chunk(54321, cx, cz, r1, ad, e, n, cs, pr, vs).is_empty():
				any = true
	ok = _chk("préférence douce : zone non vide (échantillon 7x7)", any) and ok

	print("FAUNA DETERMINISM: PASS" if ok else "FAUNA DETERMINISM: FAIL")
	quit()

func _same_roster(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].key != b[i].key or a[i].archetype != b[i].archetype or a[i].biome != b[i].biome:
			return false
		if a[i].activity != b[i].activity or absf(a[i].flee_radius - b[i].flee_radius) > 0.0001:
			return false
	return true

func _same_spawns(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].species_idx != b[i].species_idx or a[i].local.distance_to(b[i].local) > 0.0001:
			return false
		if absf(a[i].yaw - b[i].yaw) > 0.0001:
			return false
	return true

func _chk(label: String, cond: bool) -> bool:
	print(("  OK  " if cond else "  XX  "), label)
	return cond
