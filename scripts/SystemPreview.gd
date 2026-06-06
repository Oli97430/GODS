class_name SystemPreview
extends Control
## Aperçu SCHÉMATIQUE 2D d'un système (pour l'écran de départ) : étoile centrale colorée + orbites
## concentriques + planètes (taille/couleur réelles) qui tournent doucement. Léger (un _draw, pas de 3D),
## identique au bureau et au casque. Alimenté par set_system(star_color, planets).

var _star := Color(1.0, 0.95, 0.8)
var _planets: Array = []   # { rf, sz, col, ph, spd }
var _t := 0.0

func set_system(star_color: Color, planets: Array) -> void:
	_star = star_color
	_planets.clear()
	var maxorb := 0.0001
	for p in planets:
		maxorb = maxf(maxorb, p.orbit_radius)
	for i in planets.size():
		var p = planets[i]
		var rf := 0.6
		if planets.size() > 1:
			rf = lerpf(0.24, 0.96, p.orbit_radius / maxorb)
		_planets.append({
			"rf": rf,
			"sz": clampf(p.size, 0.5, 3.0),
			"col": p.color,
			"ph": p.phase,
			"spd": 0.25 + 0.45 / float(i + 1),   # les planètes internes tournent plus vite
		})
	queue_redraw()

func _process(delta: float) -> void:
	# Rien à animer tant qu'aucun système n'est sélectionné ou que l'aperçu n'est pas affiché
	# (évite de reconstruire la liste de commandes 2D à 90 Hz derrière le fondu de l'écran de départ).
	if _planets.is_empty() or not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var rad := minf(size.x, size.y) * 0.5 - 8.0
	if rad <= 1.0:
		return
	# Orbites (anneaux faibles).
	for p in _planets:
		draw_arc(c, p.rf * rad, 0.0, TAU, 56, Color(1, 1, 1, 0.10), 1.0, true)
	# Halo + étoile.
	draw_circle(c, 17.0, Color(_star.r, _star.g, _star.b, 0.22))
	draw_circle(c, 10.0, _star)
	# Planètes.
	for p in _planets:
		var a: float = p.ph + _t * p.spd
		var pos: Vector2 = c + Vector2(cos(a), sin(a)) * p.rf * rad
		draw_circle(pos, 3.0 + p.sz * 1.6, p.col)
