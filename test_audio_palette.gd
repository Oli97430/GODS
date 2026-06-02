extends SceneTree
## Phase 21 étape 6 — palette sonore de planète DÉTERMINISTE par seed : 3 planètes => 3 couleurs
## distinctes (fréquence fondamentale, partiel, filtre) ; même seed => même palette.

func _initialize() -> void:
	print("===== PALETTE PLANÈTE (déterministe par seed) =====")
	for s in [297285335, 3085501345, 2261303309]:
		var p := AmbientPlanet.new()
		p.configure(s)
		print("  seed %-11d : f0=%.1f Hz  ratio=%.3f  cutoff=%.0f Hz  part=%.2f" % [s, p._base_freq, p._ratio2, p._cutoff, p._part_amp])
		p.free()
	var a := AmbientPlanet.new()
	a.configure(12345)
	var b := AmbientPlanet.new()
	b.configure(12345)
	print("  déterminisme (même seed => même f0) : %.2f == %.2f -> %s" % [a._base_freq, b._base_freq, str(a._base_freq == b._base_freq)])
	a.free()
	b.free()
	quit()
