extends SceneTree
## Steps 7-9 : valide FLEE (fuite à l'approche du joueur), REST (cycle jour/nuit + abri par orage) et
## LOD (gel/réveil par distance). _process() est piloté À LA MAIN (set_process(false)) avec des stubs
## TimeOfDay/WeatherSystem injectés -> conditions déterministes, sans dépendre de l'heure simulée.

class StubTod:
	var alt := 1.0
	func get_sun_altitude(_d) -> float: return alt

class StubWeather:
	var storm := 0.0
	func get_storm() -> float: return storm

func _initialize() -> void:
	_run()

func _run() -> void:
	var ok := true
	var lib := FaunaLibrary.new()
	var roster := PlanetFaunaRoster.generate(12345, lib)
	var sp: Dictionary = roster[0]
	var parts: Dictionary = lib.species_parts(sp.key, sp.params)
	var mat := StandardMaterial3D.new()

	# Faux chunk (parent) + faux joueur, dans l'arbre (pour global_position / to_local).
	var chunk := Node3D.new()
	root.add_child(chunk)
	var player := Node3D.new()
	root.add_child(player)
	# L'arbre doit être « live » avant de lire global_position / to_local (sinon identité).
	await process_frame
	await process_frame

	# --- Test A : LOD gel/réveil ---
	var c := _spawn(chunk, sp, parts, mat, player)
	player.position = Vector3(300.0, 0.0, 0.0)   # très loin
	_drive(c, 12, 0.1)
	ok = _chk("LOD : gelé quand loin", c._active == false) and ok
	player.position = Vector3(4.0, 0.0, 0.0)     # tout près
	_drive(c, 12, 0.1)
	ok = _chk("LOD : réveillé quand proche", c._active == true) and ok

	# --- Test B : FLEE (proximité joueur) ---
	c._activity = PlanetFaunaRoster.Activity.DIURNAL
	var st := StubTod.new()
	st.alt = 1.0                                 # plein jour -> pas de repos
	c._tod = st
	var sw := StubWeather.new()
	c._weather = sw
	c._flee_radius = 8.0
	c.position = Vector3.ZERO
	player.position = Vector3(3.0, 0.0, 0.0)     # à 3 m, dans flee_radius
	_drive(c, 5, 0.1)
	ok = _chk("FLEE : déclenchée par proximité", c._state == Creature.State.FLEE) and ok
	ok = _chk("FLEE : s'éloigne du joueur", c.position.x < -0.3) and ok
	# Joueur immobile : la créature finit par se calmer (sort de FLEE).
	var calmed := false
	for i in 200:
		c._process(0.1)
		if c._state != Creature.State.FLEE:
			calmed = true
			break
	ok = _chk("FLEE : se calme une fois loin", calmed) and ok

	# --- Test C : REST jour/nuit + orage ---
	var c2 := _spawn(chunk, sp, parts, mat, player)
	player.position = Vector3(4.0, 0.0, 0.0)     # proche -> actif (pas gelé)
	c2._activity = PlanetFaunaRoster.Activity.DIURNAL
	c2._flee_radius = 0.0                         # pas de fuite dans ce test
	var st2 := StubTod.new()
	c2._tod = st2
	var sw2 := StubWeather.new()
	c2._weather = sw2
	st2.alt = 1.0                                # jour
	_drive(c2, 10, 0.1)
	ok = _chk("REST : diurne actif le jour", c2._state != Creature.State.REST) and ok
	st2.alt = -1.0                               # nuit
	_drive(c2, 10, 0.1)
	ok = _chk("REST : diurne se repose la nuit", c2._state == Creature.State.REST) and ok
	st2.alt = 1.0                                # retour au jour
	_drive(c2, 10, 0.1)
	ok = _chk("REST : se réveille au retour du jour", c2._state != Creature.State.REST) and ok
	# Orage au-delà de la tolérance : se met à l'abri même de jour.
	c2._storm_sens = 0.5
	sw2.storm = 0.9
	_drive(c2, 10, 0.1)
	ok = _chk("REST : abri par gros orage (même de jour)", c2._state == Creature.State.REST) and ok

	print("FAUNA BEHAVIOR: PASS" if ok else "FAUNA BEHAVIOR: FAIL")
	quit()

func _spawn(chunk: Node3D, sp: Dictionary, parts: Dictionary, mat: Material, player: Node3D) -> Creature:
	var c := Creature.new()
	chunk.add_child(c)
	c.position = Vector3.ZERO
	c.setup(sp, parts, mat, player, null, 777)   # ground=null : IA pure, pas de collage au sol
	c.set_process(false)                          # on pilote _process() manuellement
	return c

func _drive(c, frames: int, dt: float) -> void:
	for i in frames:
		c._process(dt)

func _chk(label: String, cond: bool) -> bool:
	print(("  OK  " if cond else "  XX  "), label)
	return cond
