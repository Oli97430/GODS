shader_type spatial;
// Halo atmosphérique ENRICHI (amélioration planètes) : halo fresnel large + LISERÉ vif au limbe
// + BANDE CHAUDE au terminateur (effet lever/coucher de soleil) + côté nuit sombre. Additif, non
// éclairé, SANS raymarching (coût stéréo casque maîtrisé) : une seule sphère transparente.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 atmo_color : source_color = vec3(0.35, 0.55, 1.0);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.42, 0.18); // teinte chaude au terminateur
uniform float density : hint_range(0.0, 3.0) = 1.0;
uniform float fresnel_power : hint_range(1.0, 8.0) = 2.6;  // halo large (plus bas = halo plus épais)
uniform float rim_power : hint_range(1.0, 16.0) = 7.0;     // liseré fin et vif au bord du disque
uniform float night_floor : hint_range(0.0, 1.0) = 0.05;   // lueur résiduelle côté nuit
uniform float sunset_strength : hint_range(0.0, 1.0) = 0.8; // intensité de la bande chaude
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);          // direction VERS le soleil (monde)

varying vec3 v_world_normal;

void vertex() {
	// Normale monde (sphère à échelle uniforme) pour le terme jour/nuit.
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// Fresnel en espace vue : ~0 face caméra (centre), ~1 sur le limbe.
	float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndotv, fresnel_power);   // halo large
	float rim = pow(1.0 - ndotv, rim_power);        // liseré vif au tout bord
	// Terme jour/nuit : lit_s in [-1,1] (1 = plein soleil, -1 = nuit).
	float lit_s = dot(normalize(v_world_normal), normalize(sun_direction));
	float day = mix(night_floor, 1.0, clamp(lit_s * 0.5 + 0.5, 0.0, 1.0));
	// Bande chaude au TERMINATEUR (jour/nuit) : pic là où lit_s ~ 0 (lever/coucher).
	float term = smoothstep(0.35, 0.0, abs(lit_s)) * sunset_strength;
	vec3 col = mix(atmo_color, sunset_color, term);
	// Additif : couleur émise = col * ALPHA. Le liseré renforce le bord du disque.
	float glow = (fres + rim * 1.6) * density * day;
	ALBEDO = col;
	ALPHA = clamp(glow, 0.0, 1.0);
}
