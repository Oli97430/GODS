shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, shadows_disabled, depth_draw_never, fog_disabled;
// Rai de lumière sous-marin (god ray) : quad vertical doux, plus lumineux vers le HAUT (surface) et au
// CENTRE, scintillement lent. ADDITIF. `intensity` poussée par le CPU (0 = nuit / au-dessus de l'eau /
// profond => invisible). FONDU sous la surface (world Y) => aucun rai ne dépasse dans l'air au-dessus de
// l'eau. depth_draw_never => occulté par le terrain mais n'écrit pas le Z.

uniform vec3 shaft_col : source_color = vec3(0.55, 0.74, 0.88);
uniform float intensity = 0.0;

varying float v_worldy;

void vertex() {
	v_worldy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;   // Y monde du fragment (pour couper à la surface)
}

void fragment() {
	float hx = abs(UV.x - 0.5) * 2.0;            // 0 centre -> 1 bord
	float horiz = smoothstep(1.0, 0.15, hx);     // doux, éteint sur les bords
	float vert = UV.y * UV.y;                     // plus lumineux vers la surface (haut du quad)
	float below = smoothstep(0.4, -1.2, v_worldy);   // 1 sous la mer (Y0), 0 au-dessus => pas de rai dans l'air
	float shimmer = 0.7 + 0.3 * sin(TIME * 1.3 + UV.x * 7.0);
	ALBEDO = shaft_col;
	ALPHA = horiz * vert * below * intensity * shimmer * 0.6;
}
