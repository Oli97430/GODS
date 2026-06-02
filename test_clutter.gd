extends SceneTree
## Phase 20 couche B — validation du clutter (logique pure, hors rendu) :
##   1) meshes : tris par variante (bas-poly, non vides) ;
##   2) semis : instances par catégorie sur une grille de chunks (présence selon biome) ;
##   3) déterminisme : même chunk généré 2× => identique.

func _initialize() -> void:
	var lib := ClutterLibrary.new()
	print("===== CLUTTER — triangles par variante =====")
	var names := ["pebbleA", "pebbleB", "twigA", "twigB", "boneA", "boneB", "leafDry", "leafFresh", "shell"]
	var ok_tris := true
	for v in ClutterLibrary.VARIANT_COUNT:
		var tc := lib.tri_count(v)
		if tc <= 0:
			ok_tris = false
		print("  %-10s : %d tris" % [names[v], tc])
	print("  meshes non vides : %s" % str(ok_tris))

	var phys := SurfaceGenerator.DEFAULT_PLANET_PHYS_RADIUS
	var vscale := SurfaceGenerator.DEFAULT_VERTICAL_SCALE
	var gseed := 20250601
	var anchor := Vector3(0.3, 0.9, 0.2).normalized()
	var b := FloatingOrigin.tangent_basis(anchor)
	var east = b.x
	var north = b.z

	print("\n===== CLUTTER — semis sur 7x7 chunks (seed %d) =====" % gseed)
	var tot := {}
	var chunks_with := 0
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			var out: Dictionary = ClutterSeeder.seed_chunk(gseed, cx, cz, anchor, east, north, 256.0, phys, vscale)
			if not out.is_empty():
				chunks_with += 1
			for v in out:
				tot[v] = int(tot.get(v, 0)) + out[v].size()
	for v in ClutterLibrary.VARIANT_COUNT:
		print("  %-10s : %d instances" % [names[v], int(tot.get(v, 0))])
	print("  chunks non vides : %d / 49" % chunks_with)

	# Déterminisme : même chunk généré deux fois => mêmes comptes par variante.
	var a1: Dictionary = ClutterSeeder.seed_chunk(gseed, 1, 1, anchor, east, north, 256.0, phys, vscale)
	var a2: Dictionary = ClutterSeeder.seed_chunk(gseed, 1, 1, anchor, east, north, 256.0, phys, vscale)
	var same := a1.size() == a2.size()
	for v in a1:
		if not a2.has(v) or a1[v].size() != a2[v].size():
			same = false
	print("\nDÉTERMINISME (même chunk 2× identique) : %s" % str(same))
	quit()
