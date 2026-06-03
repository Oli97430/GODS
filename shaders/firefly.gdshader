shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Lucioles / spores nocturnes : petits quads BILLBOARD additifs, lueur radiale douce + scintillement +
// dérive lente — TOUT dans le shader (TIME + phases d'instance) => zéro coût CPU par frame. Stéréo-correct
// (billboard reconstruit par-œil via VIEW/PROJECTION). INSTANCE_CUSTOM par luciole (VERTEX uniquement,
// relayé au fragment via varying) :  .x = phase scintillement · .y = phase dérive · .z = échelle · .w = teinte

uniform float amount = 0.0;                                   // densité visible (0 jour -> 1 nuit) : pilote l'alpha
uniform vec3 col_a : source_color = vec3(0.55, 1.0, 0.35);   // vert
uniform vec3 col_b : source_color = vec3(1.0, 0.72, 0.25);   // ambre
uniform float drift = 0.35;                                   // amplitude de dérive (m)

varying vec4 v_custom;   // INSTANCE_CUSTOM relayé au fragment (.x scintillement, .w teinte)

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	float sc = 0.02 + INSTANCE_CUSTOM.z * 0.05;               // taille 2..7 cm
	float dp = INSTANCE_CUSTOM.y * 6.2831;
	vec3 wob = vec3(sin(TIME * 0.6 + dp), sin(TIME * 0.45 + dp * 1.7 + 1.3), cos(TIME * 0.55 + dp * 1.3)) * drift;
	vec3 c_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + wob;   // centre instance (monde) + dérive
	vec3 c_view = (VIEW_MATRIX * vec4(c_world, 1.0)).xyz;                 // -> espace vue
	c_view.xy += VERTEX.xy * sc;                                         // billboard : étale le quad face caméra
	POSITION = PROJECTION_MATRIX * vec4(c_view, 1.0);
}

void fragment() {
	float r = length(UV - vec2(0.5));
	float glow = smoothstep(0.5, 0.0, r);                                // lueur radiale douce
	float flick = 0.5 + 0.5 * sin(TIME * 3.0 + v_custom.x * 40.0);       // scintillement par luciole
	ALBEDO = mix(col_a, col_b, v_custom.w);
	ALPHA = glow * flick * amount;                                       // additif (blend_add) : intensité = alpha
}
