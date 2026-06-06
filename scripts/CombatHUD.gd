extends Control
## HUD COMBAT (bureau) : barre de PV (bas-centre) + vague + score (haut-droite), et bandeau « ÉLIMINÉ » à la
## mort. Affiché seulement quand le combat est actif (arme équipée) ET en SURFACE ET hors XR (le casque utilise
## la surcouche 3D + la montre). Lit GameState (blackboard combat). AUTO-CONTENU, aucun couplage au joueur.

const BAR_W := 360.0
const BAR_H := 22.0

var _font: Font
var _t := 0.0            # horloge pour les pulsations
var _last_wave := 0      # détection de changement de vague
var _announce_t := 0.0   # minuterie du bandeau « VAGUE N »

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Plein écran : on dessine en coordonnées absolues dans _draw.
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = false

func _process(dt: float) -> void:
	var show: bool = GameState.combat_active and not GameState.xr_active \
		and GameState.current_scale == GameState.Scale.SURFACE
	if show != visible:
		visible = show
	if not show:
		_last_wave = 0
		_announce_t = 0.0
		return
	_t += dt
	if GameState.combat_wave > _last_wave:   # nouvelle vague => bandeau d'annonce
		if GameState.combat_wave > 0:
			_announce_t = 2.2
		_last_wave = GameState.combat_wave
	elif GameState.combat_wave < _last_wave:
		_last_wave = GameState.combat_wave    # reset de session
	if _announce_t > 0.0:
		_announce_t = maxf(_announce_t - dt, 0.0)
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	# --- Barre de PV (bas-centre) ---
	var ratio := 0.0
	if GameState.combat_hp_max > 0.0:
		ratio = clampf(GameState.combat_hp / GameState.combat_hp_max, 0.0, 1.0)
	var bx := (vp.x - BAR_W) * 0.5
	var by := vp.y - 64.0
	draw_rect(Rect2(bx - 2, by - 2, BAR_W + 4, BAR_H + 4), Color(0, 0, 0, 0.5), true)
	draw_rect(Rect2(bx, by, BAR_W, BAR_H), Color(0.10, 0.10, 0.12, 0.85), true)
	var fill := Color(0.30, 0.85, 0.40).lerp(Color(0.90, 0.20, 0.18), 1.0 - ratio)   # vert plein → rouge bas
	if ratio < 0.3 and not GameState.combat_dead:
		fill = fill.lerp(Color(1.0, 0.12, 0.10), (0.5 + 0.5 * sin(_t * 9.0)) * 0.7)   # pulse d'alerte PV bas
	draw_rect(Rect2(bx, by, BAR_W * ratio, BAR_H), fill, true)
	# Bouclier en sus (améliorations ramassées) : segment cyan à droite des PV.
	if GameState.combat_overshield > 0.0 and GameState.combat_hp_max > 0.0:
		var os := clampf(GameState.combat_overshield / GameState.combat_hp_max, 0.0, 1.0)
		var ox := bx + BAR_W * ratio
		var ow := minf(BAR_W * os, BAR_W - BAR_W * ratio)
		if ow > 0.0:
			draw_rect(Rect2(ox, by, ow, BAR_H), Color(0.35, 0.8, 1.0, 0.9), true)
	draw_rect(Rect2(bx, by, BAR_W, BAR_H), Color(1, 1, 1, 0.25), false, 1.0)
	var hp_txt := "PV %d / %d" % [int(round(GameState.combat_hp)), int(round(GameState.combat_hp_max))]
	if GameState.combat_overshield > 0.0:
		hp_txt += "  (+%d)" % int(round(GameState.combat_overshield))
	var hs := _font.get_string_size(hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(_font, Vector2(bx + (BAR_W - hs.x) * 0.5, by + BAR_H - 5), hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.95))
	# --- Vague + score (haut-droite) ---
	var info := "Vague %d     Score %d" % [GameState.combat_wave, GameState.combat_score]
	var isz := _font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var ix := vp.x - isz.x - 24.0
	var iy := 34.0
	draw_string(_font, Vector2(ix + 1, iy + 1), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 0, 0, 0.6))
	draw_string(_font, Vector2(ix, iy), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.86, 0.45))
	# Améliorations actives (sous le score, haut-droite).
	var bf := ""
	if GameState.combat_dmg_mult > 1.001:
		bf += "DGT x%.1f   " % GameState.combat_dmg_mult
	if GameState.combat_firerate_mult > 1.001:
		bf += "CAD x%.1f" % GameState.combat_firerate_mult
	bf = bf.strip_edges()
	if bf != "":
		var bsz := _font.get_string_size(bf, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(_font, Vector2(vp.x - bsz.x - 24.0, iy + 26.0), bf, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.95, 0.72))
	# --- Annonce de nouvelle vague ---
	if _announce_t > 0.0 and not GameState.combat_dead:
		var a := clampf(_announce_t / 0.5, 0.0, 1.0)   # fondu sur la dernière 0,5 s
		var wtxt := "VAGUE %d" % GameState.combat_wave
		var ws := _font.get_string_size(wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 44)
		var wx := (vp.x - ws.x) * 0.5
		var wy := vp.y * 0.26
		draw_string(_font, Vector2(wx + 2, wy + 2), wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(0, 0, 0, 0.5 * a))
		draw_string(_font, Vector2(wx, wy), wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1.0, 0.55, 0.2, a))
	# --- Prompt « mode Drone ? » (sortie d'arme : on demande avant de lancer les vagues) ---
	if GameState.drone_mode_prompt:
		var q := "MODE DRONE ?"
		var qs := _font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, 44)
		draw_string(_font, Vector2((vp.x - qs.x) * 0.5 + 2, vp.y * 0.34 + 2), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(0, 0, 0, 0.5))
		draw_string(_font, Vector2((vp.x - qs.x) * 0.5, vp.y * 0.34), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1.0, 0.55, 0.2))
		var hh := "[Entrée] Oui      ·      [Retour arr.] Non"
		var hsz := _font.get_string_size(hh, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
		draw_string(_font, Vector2((vp.x - hsz.x) * 0.5, vp.y * 0.34 + 42.0), hh, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.92))
	# --- Bandeau de mort ---
	if GameState.combat_dead:
		var t1 := "ÉLIMINÉ"
		var t1s := _font.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 52)
		draw_string(_font, Vector2((vp.x - t1s.x) * 0.5, vp.y * 0.5 - 18), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(1.0, 0.35, 0.30))
		var tr := "Vague atteinte %d   —   Score %d" % [GameState.combat_result_wave, GameState.combat_result_score]
		var trs := _font.get_string_size(tr, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		draw_string(_font, Vector2((vp.x - trs.x) * 0.5, vp.y * 0.5 + 22), tr, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.86, 0.45))
		var t2 := "Réapparition…"
		var t2s := _font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		draw_string(_font, Vector2((vp.x - t2s.x) * 0.5, vp.y * 0.5 + 56), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.80))
