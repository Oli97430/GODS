extends SceneTree
## Phase 20 couche C — validation des POI (logique pure, hors rendu) :
##   1) générateurs : les 16 catégories produisent un Node3D non vide (meshes + tris + particules) ;
##   2) distributor : taux de présence (~9 %), variété de catégories, nommage des notables, déterminisme.

func _count_tris(node: Node) -> int:
	var t := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var m: Mesh = (node as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			t += verts.size() / 3
	for c in node.get_children():
		t += _count_tris(c)
	return t

func _count_class(node: Node, cls: String) -> int:
	var n := 1 if node.is_class(cls) else 0
	for c in node.get_children():
		n += _count_class(c, cls)
	return n

func _initialize() -> void:
	var lib := POILibrary.new()
	var names: Array = POILibrary.CATEGORY_NAMES
	print("===== POI — 16 générateurs =====")
	var ok := true
	for cat in POILibrary.CATEGORY_COUNT:
		var node := lib.generate(cat, 12345 + cat * 7919)
		var tris := _count_tris(node)
		var meshes := _count_class(node, "MeshInstance3D")
		var parts := _count_class(node, "GPUParticles3D")
		var tag := "nommé " if POILibrary.is_named(cat) else "      "
		if node == null or tris < 12:
			ok = false
		print("  %-22s [%s] : %4d tris  %d mesh  %d part" % [names[cat], tag, tris, meshes, parts])
		node.free()
	print("  tous générés (>=12 tris) : %s" % str(ok))

	var phys := SurfaceGenerator.DEFAULT_PLANET_PHYS_RADIUS
	var vscale := SurfaceGenerator.DEFAULT_VERTICAL_SCALE
	var gseed := 20250601
	var anchor := Vector3(0.25, 0.86, 0.45).normalized()
	var b := FloatingOrigin.tangent_basis(anchor)
	var east = b.x
	var north = b.z

	print("\n===== POI — distribution sur 41x41 chunks =====")
	var total := 0
	var present := 0
	var named := 0
	var hist := {}
	for cz in range(-20, 21):
		for cx in range(-20, 21):
			total += 1
			var poi: POIInstance = POIDistributor.seed_chunk(gseed, cx, cz, 1, anchor, east, north, 256.0, phys, vscale)
			if poi != null:
				present += 1
				hist[poi.category] = int(hist.get(poi.category, 0)) + 1
				if poi.is_named():
					named += 1
	print("  présence : %d / %d chunks (%.1f%%)" % [present, total, 100.0 * present / float(total)])
	print("  POI nommés : %d / %d" % [named, present])
	var distinct := 0
	for cat in POILibrary.CATEGORY_COUNT:
		if hist.has(cat):
			distinct += 1
			print("    %-22s : %d" % [names[cat], hist[cat]])
	print("  catégories distinctes rencontrées : %d / 16" % distinct)

	# Déterminisme : même chunk généré 2× => même résultat (catégorie + nom).
	var p1: POIInstance = POIDistributor.seed_chunk(gseed, 6, 9, 1, anchor, east, north, 256.0, phys, vscale)
	var p2: POIInstance = POIDistributor.seed_chunk(gseed, 6, 9, 1, anchor, east, north, 256.0, phys, vscale)
	var det := (p1 == null and p2 == null) or (p1 != null and p2 != null and p1.category == p2.category and p1.poi_name == p2.poi_name)
	print("\nDÉTERMINISME (même chunk 2×) : %s" % str(det))
	quit()
