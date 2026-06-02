extends SceneTree
## Phase 21 : navigation ABSTRAITE (sans vaisseau). Boot en GALAXY, puis descente par sélection
## GALAXY -> SYSTEM -> PLANET -> SURFACE (à pied), et remontées. Aucune erreur, scales corrects.
## (GameState est accédé via /root/GameState : autoload non résolu comme global dans un script -s.)

const GALAXY := 0
const SYSTEM := 1
const PLANET := 2
const SURFACE := 3

func _initialize() -> void:
	_run()

func _run() -> void:
	var ok := true
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var gs = root.get_node("/root/GameState")
	var vm = main.get_node("ViewManager")
	var sysview = main.get_node("SystemView")

	ok = _chk("boot en GALAXY", gs.current_scale == GALAXY) and ok

	# Trouve un système avec des planètes (certains sont vides).
	var gi := -1
	for i in 30:
		vm.enter_system(i)
		await process_frame
		if sysview.data != null and sysview.data.planets.size() > 0:
			gi = i
			break
		vm.exit_to_galaxy()
		await process_frame
	ok = _chk("GALAXY->SYSTEM (système peuplé trouvé)", gi >= 0 and gs.current_scale == SYSTEM) and ok

	if gi >= 0:
		vm.enter_planet(0)
		await process_frame
		ok = _chk("SYSTEM->PLANET", gs.current_scale == PLANET) and ok

		vm.enter_surface()
		var f := 0
		while f < 400 and gs.current_scale != SURFACE:
			f += 1
			await process_frame
		ok = _chk("PLANET->SURFACE (à pied)", gs.current_scale == SURFACE) and ok
		for k in 120:
			await process_frame
		var player = main.get_node("SurfaceView").get_player()
		ok = _chk("joueur à pied présent", player != null) and ok

		vm.exit_to_planet()
		await process_frame
		ok = _chk("SURFACE->PLANET", gs.current_scale == PLANET) and ok
		vm.exit_to_system()
		await process_frame
		ok = _chk("PLANET->SYSTEM", gs.current_scale == SYSTEM) and ok

	vm.exit_to_galaxy()
	await process_frame
	ok = _chk("SYSTEM->GALAXY", gs.current_scale == GALAXY) and ok

	print("ABSTRACT NAV: PASS" if ok else "ABSTRACT NAV: FAIL")
	quit()

func _chk(label: String, cond: bool) -> bool:
	print(("  OK  " if cond else "  XX  "), label)
	return cond
