extends Control
## Boussole HUD (bureau) : bande de cap horizontale (N/E/S/O + degrés) qui défile selon l'orientation de
## la caméra active. Affichée seulement à l'échelle SURFACE (sur une planète ET en vol). North = -Z monde.
## Lit `get_viewport().get_camera_3d()` => aucun couplage au joueur. Masquée en XR (HUD plat).

const W := 460.0
const H := 46.0
const DEG_PER_PX := 0.34   # ° par pixel (~90° visibles sur la largeur)
const LABELS := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}

var _heading := 0.0
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -W * 0.5
	offset_right = W * 0.5
	offset_top = 14.0
	offset_bottom = 14.0 + H
	visible = false

func _process(_dt: float) -> void:
	if GameState.current_scale != GameState.Scale.SURFACE or GameState.xr_active:
		if visible:
			visible = false
		return   # HUD plat masqué hors-surface / en XR : on n'interroge même pas la caméra
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		if visible:
			visible = false
		return
	visible = true
	var fwd := -cam.global_transform.basis.z
	_heading = fmod(rad_to_deg(atan2(fwd.x, -fwd.z)) + 360.0, 360.0)   # 0 = -Z (Nord), croît vers l'Est
	queue_redraw()

func _draw() -> void:
	var cx := W * 0.5
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.35), true)
	draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, 0.22), false, 1.0)
	var half_span := (W * 0.5) * DEG_PER_PX   # ° visibles de part et d'autre du centre
	var a := int(floor((_heading - half_span) / 15.0)) * 15
	var stop := int(ceil((_heading + half_span) / 15.0)) * 15
	while a <= stop:
		var rel := wrapf(float(a) - _heading, -180.0, 180.0)
		var x := cx + rel / DEG_PER_PX
		if x >= 3.0 and x <= W - 3.0:
			var amod := ((a % 360) + 360) % 360
			if LABELS.has(amod):
				var major := amod % 90 == 0
				draw_line(Vector2(x, H - 16), Vector2(x, H - 2), Color(1, 1, 1, 0.85), 2.0 if major else 1.0)
				var lbl: String = LABELS[amod]
				var col := Color(1.0, 0.82, 0.35) if amod == 0 else Color(1, 1, 1, 0.9)
				var sz := _font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
				draw_string(_font, Vector2(x - sz.x * 0.5, H - 20), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
			else:
				draw_line(Vector2(x, H - 9), Vector2(x, H - 2), Color(1, 1, 1, 0.5), 1.0)
		a += 15
	# Index central + lecture numérique du cap.
	draw_line(Vector2(cx, 2), Vector2(cx, H - 2), Color(1.0, 0.3, 0.3, 0.95), 2.0)
	var txt := "%03d°" % int(round(_heading))
	var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	draw_string(_font, Vector2(cx - ts.x * 0.5, 13), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.95))
