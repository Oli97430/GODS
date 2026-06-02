extends Control
## Logo « GODS VR » dessiné par code (sans asset image) : emblème céleste (planète + anneau
## d'orbite + lune + étoiles) au-dessus du wordmark. Rendu dans un SubViewport transparent par
## TitleScreen, puis affiché en splash de démarrage (TextureRect bureau + quad devant la caméra XR).

const W := 1024.0
const H := 512.0
const ACCENT := Color(0.30, 0.85, 0.92)   # turquoise (rappel eau / atmosphère du jeu)

func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	queue_redraw()

func _draw() -> void:
	var cx := W * 0.5
	var pc := Vector2(cx, 172.0)   # centre de la planète-emblème
	var pr := 62.0

	# --- Étoiles (semis déterministe par LCG ; évitées sur le disque planète) ---
	var s := 991
	for i in 54:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		var sx := float(s % 1024)
		s = (s * 1103515245 + 12345) & 0x7fffffff
		var sy := float(s % 320)
		if Vector2(sx, sy).distance_to(pc) < pr + 26.0:
			continue
		s = (s * 1103515245 + 12345) & 0x7fffffff
		var sz := 0.5 + float(s % 100) / 100.0 * 1.7
		draw_circle(Vector2(sx, sy), sz, Color(0.82, 0.90, 1.0, 0.35 + 0.30 * sz))

	# --- Anneau d'orbite (ellipse) ---
	var ring := PackedVector2Array()
	for k in 65:
		var a := TAU * float(k) / 64.0
		ring.append(pc + Vector2(cos(a) * (pr + 54.0), sin(a) * (pr + 20.0)))
	draw_polyline(ring, Color(ACCENT, 0.55), 2.0, true)

	# --- Planète : disque dégradé (cercles concentriques décalés vers la lumière) ---
	var rr := int(pr)
	while rr > 0:
		var t := 1.0 - float(rr) / pr
		var off := Vector2(-0.36, -0.42) * (pr - float(rr))
		var col := Color(0.09, 0.17, 0.31).lerp(Color(0.36, 0.64, 0.80), t)
		draw_circle(pc + off, float(rr), col)
		rr -= 2
	draw_arc(pc, pr, -2.3, 0.5, 28, Color(0.65, 0.88, 0.97, 0.45), 3.0, true)   # croissant éclairé
	# Lune sur l'anneau
	var ma := -0.7
	draw_circle(pc + Vector2(cos(ma) * (pr + 54.0), sin(ma) * (pr + 20.0)), 5.5, Color(0.86, 0.89, 0.96))

	# --- Wordmark « GODS VR » (GODS clair + VR turquoise) ---
	var font := ThemeDB.fallback_font
	var fs := 152
	var gods := "GODS"
	var vr := "VR"
	var gap := 30.0
	var w_gods := font.get_string_size(gods, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w_vr := font.get_string_size(vr, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x0 := cx - (w_gods + gap + w_vr) * 0.5
	var baseline := 398.0
	var shadow := Color(0.0, 0.0, 0.0, 0.55)
	draw_string_outline(font, Vector2(x0, baseline), gods, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, shadow)
	draw_string(font, Vector2(x0, baseline), gods, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.94, 0.97, 1.0))
	var xv := x0 + w_gods + gap
	draw_string_outline(font, Vector2(xv, baseline), vr, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, shadow)
	draw_string(font, Vector2(xv, baseline), vr, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ACCENT)

	# --- Tagline ---
	var tag := "EXPLORATEUR SPATIAL"
	var tfs := 30
	var w_tag := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	draw_string(font, Vector2(cx - w_tag * 0.5, baseline + 54.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0.62, 0.74, 0.86, 0.9))
