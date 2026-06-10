shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Étoiles de nuit (phase 12) : quads billboardés additifs, une instance MultiMesh par autre
// système de la galaxie. Couleur = type spectral (COLOR par instance). Luminosité globale
// 'night' poussée par Starfield (0 jour => invisible, 1 nuit). depth_draw_never + depth_test
// par défaut : le terrain occulte le dôme sous l'horizon, le ciel le laisse passer au-dessus.

#include "res://shaders/cloud_occlusion.gdshaderinc"

uniform float night = 0.0;
varying float v_tw;   // facteur de scintillement précalculé en vertex (petites étoiles seulement)
varying vec3 v_cdir;  // direction MONDE de l'étoile (pour l'occlusion par les nuages)

float h13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	// Billboard face-caméra : conserve la position (col 3) + l'échelle (longueurs col 0/1).
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	// Scintillement : phase par position, vitesse par étoile. SEULEMENT les petites (<8 m) =>
	// les grosses lueurs (Voie lactée) ne clignotent pas.
	float ph = h13(MODEL_MATRIX[3].xyz);
	float tw = 0.62 + 0.38 * sin(TIME * (1.4 + ph * 2.2) + ph * 6.2831853);
	v_tw = mix(1.0, tw, step(sx, 8.0));
	v_cdir = normalize(MODEL_MATRIX[3].xyz - CAMERA_POSITION_WORLD);   // direction monde de l'étoile
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		MAIN_CAM_INV_VIEW_MATRIX[0] * sx,
		MAIN_CAM_INV_VIEW_MATRIX[1] * sy,
		MAIN_CAM_INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	// Disque radial doux à cœur net.
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;
	float a = smoothstep(1.0, 0.0, r);
	a *= a;
	ALBEDO = COLOR.rgb;
	ALPHA = a * night * v_tw * cloud_transmittance(v_cdir);   // estompée si un nuage passe devant
}
