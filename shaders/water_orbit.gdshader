shader_type spatial;
// Océan ORBITAL amélioré : eau stylisée sur une sphère au niveau de mer. Dégradé profondeur->limbe,
// JOUR/NUIT (l'eau s'assombrit côté non éclairé, comme la terre), reflet spéculaire du soleil large
// et doux UNIQUEMENT côté jour, fresnel vers le ciel, léger scintillement. NON éclairé (apparence
// calculée à la main) => rendu cohérent et stable en stéréo.
render_mode unshaded, cull_back;

uniform vec4 water_color : source_color = vec4(0.05, 0.28, 0.45, 1.0);
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);   // monde, VERS le soleil
uniform float wave_time = 0.0;
uniform float night_floor : hint_range(0.0, 1.0) = 0.06;  // luminosité résiduelle côté nuit

varying vec3 v_world_normal;

void vertex() {
	// Normale monde (sphère à échelle uniforme) pour le terme jour/nuit.
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 4.0);
	// Dégradé : centre = eau profonde (sombre), limbe = plus clair (reflet du ciel).
	vec3 col = mix(water_color.rgb * 0.5, water_color.rgb * 1.5 + vec3(0.08), fres);
	// Jour/nuit : l'eau s'assombrit sur la face non éclairée (réagit au soleil comme la terre).
	float lit = clamp(dot(normalize(v_world_normal), normalize(sun_direction)), 0.0, 1.0);
	float day = mix(night_floor, 1.0, lit);
	col *= day;
	// Reflet spéculaire du soleil (espace vue), large et doux, UNIQUEMENT côté éclairé.
	vec3 sun_vs = normalize((VIEW_MATRIX * vec4(sun_direction, 0.0)).xyz);
	vec3 refl = reflect(-v, n);
	float glint = pow(max(dot(refl, sun_vs), 0.0), 60.0);
	float shimmer = 0.85 + 0.15 * sin(wave_time * 0.7 + UV.x * 40.0);
	col += vec3(1.0, 0.96, 0.86) * glint * 1.8 * shimmer * lit;   // * lit => pas de reflet la nuit
	ALBEDO = col;
}
