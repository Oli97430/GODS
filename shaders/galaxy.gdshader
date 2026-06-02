shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Galaxies lointaines (ciel de nuit) : billboards additifs face-caméra. Cœur elliptique brillant +
// halo doux + bras spiraux procéduraux, orientés/typés PAR INSTANCE via INSTANCE_CUSTOM :
//   x = angle de rotation, y = ellipticité (inclinaison), z = type (>0.5 = spirale), w = phase des bras.
// Couleur = teinte par instance (COLOR). Luminosité globale 'night' (0 jour => invisible). Même dôme
// que les étoiles (depth_draw_never => occlusion terrain sous l'horizon, ciel laisse passer au-dessus).

uniform float night = 0.0;
varying vec4 vc;

void vertex() {
	vc = INSTANCE_CUSTOM;
	// Billboard face-caméra : conserve position (col 3) + échelle (longueurs col 0/1).
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		MAIN_CAM_INV_VIEW_MATRIX[0] * sx,
		MAIN_CAM_INV_VIEW_MATRIX[1] * sy,
		MAIN_CAM_INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 c = (UV - vec2(0.5)) * 2.0;          // -1..1
	float ca = cos(vc.x);
	float sa = sin(vc.x);
	vec2 p = vec2(c.x * ca - c.y * sa, c.x * sa + c.y * ca);
	p.y /= mix(0.40, 0.95, vc.y);             // ellipticité (galaxie vue inclinée)
	float r = length(p);
	float core = exp(-r * r * 7.0);           // cœur lumineux compact
	float halo = smoothstep(1.0, 0.0, r);     // halo doux jusqu'au bord
	halo *= halo * 0.35;
	float arms = 0.0;
	if (vc.z > 0.5) {                          // bras spiraux (log-spirale à 2 bras)
		float th = atan(p.y, p.x);
		float s = cos(2.0 * th - 7.0 * log(r + 0.12) + vc.w * 6.2831853);
		arms = smoothstep(0.4, 1.0, s) * smoothstep(0.06, 0.35, r) * smoothstep(1.0, 0.35, r) * 0.5;
	}
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(core + halo + arms, 0.0, 1.0) * night;
}
