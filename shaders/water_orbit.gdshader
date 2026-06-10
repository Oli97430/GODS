shader_type spatial;
// Océan ORBITAL enrichi : eau stylisée sur une sphère au niveau de mer. Dégradé profondeur->limbe
// teinté par le CIEL (atmo_color), JOUR/NUIT (l'eau s'assombrit côté non éclairé), reflet spéculaire
// du soleil large + SCINTILLEMENT (champ de paillettes animé) côté jour, fresnel vers le ciel. NON
// éclairé (apparence calculée à la main) => rendu cohérent et stable en stéréo.
render_mode unshaded, cull_back;

uniform vec4 water_color : source_color = vec4(0.05, 0.28, 0.45, 1.0);
uniform vec3 atmo_color : source_color = vec3(0.45, 0.62, 1.0);   // teinte de ciel reflétée au limbe
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);   // monde, VERS le soleil
uniform float wave_time = 0.0;
uniform float night_floor : hint_range(0.0, 1.0) = 0.06;  // luminosité résiduelle côté nuit

varying vec3 v_world_normal;
varying vec3 v_local_dir;   // direction OBJET (stable sur la surface) -> champ de paillettes

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	// Normale monde (sphère à échelle uniforme) pour le terme jour/nuit.
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_local_dir = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 4.0);
	// Dégradé : centre = eau profonde (sombre), limbe = plus clair, teinté par le CIEL (reflet d'atmosphère).
	vec3 deep = water_color.rgb * 0.5;
	vec3 shallow = mix(water_color.rgb * 1.4 + vec3(0.06), atmo_color, 0.35);
	vec3 col = mix(deep, shallow, fres);
	// Jour/nuit : l'eau s'assombrit sur la face non éclairée (réagit au soleil comme la terre).
	float lit = clamp(dot(normalize(v_world_normal), normalize(sun_direction)), 0.0, 1.0);
	float day = mix(night_floor, 1.0, lit);
	col *= day;
	// Reflet spéculaire du soleil (espace vue), large et doux, UNIQUEMENT côté éclairé.
	vec3 sun_vs = normalize((VIEW_MATRIX * vec4(sun_direction, 0.0)).xyz);
	vec3 refl = reflect(-v, n);
	float glint = pow(max(dot(refl, sun_vs), 0.0), 60.0);
	// SCINTILLEMENT : champ de paillettes (bruit animé en espace objet) qui module le reflet -> mer pétillante.
	float sp = vnoise(v_local_dir * 130.0 + vec3(0.0, wave_time * 0.9, 0.0));
	float sparkle = smoothstep(0.55, 0.85, sp);
	col += vec3(1.0, 0.96, 0.86) * glint * (0.7 + 1.8 * sparkle) * 1.6 * lit;   // * lit => pas de reflet la nuit
	ALBEDO = col;
}
