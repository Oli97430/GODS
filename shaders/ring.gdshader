shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled, unshaded;
// Anneau planétaire (phase 14) : disque plat masqué en couronne par le rayon, densité radiale
// variable (bandes/gaps procéduraux), léger fresnel rasant + rétro-éclairage par l'étoile.
// Géométrie en unités de RAYON PLANÈTE (VERTEX local) ; le node est mis à l'échelle ensuite.

uniform vec3 ring_tint : source_color = vec3(0.80, 0.72, 0.58);
uniform float inner_radius = 1.5;
uniform float outer_radius = 2.8;
uniform float opacity = 0.55;
uniform float density_seed = 0.0;
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);

varying vec3 v_local;
varying vec3 v_world_normal;

void vertex() {
	v_local = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Densité radiale : bandes/gaps pseudo-aléatoires (déterministes par density_seed).
float ring_density(float r) {
	float n = 0.55 + 0.30 * sin(r * 21.0 + density_seed * 40.0) + 0.15 * sin(r * 53.0 + density_seed * 90.0);
	return clamp(n, 0.0, 1.0);
}

void fragment() {
	float r = length(v_local.xz);
	if (r < inner_radius || r > outer_radius) {
		discard;
	}
	// Adoucissement des bords interne/externe.
	float edge = smoothstep(inner_radius, inner_radius + 0.05, r) * smoothstep(outer_radius, outer_radius - 0.08, r);
	float dens = ring_density(r) * edge;
	// Fresnel rasant (vue space) : l'anneau brille en bord de tranche.
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	// Rétro-éclairage : l'étoile rasant le plan de l'anneau le fait diffuser (approximation).
	float graze = 1.0 - abs(dot(normalize(sun_direction), normalize(v_world_normal)));
	vec3 col = ring_tint * (0.8 + 0.6 * fres + 0.4 * graze);
	ALBEDO = col;
	ALPHA = clamp(dens * opacity * (0.7 + 0.5 * fres), 0.0, 1.0);
}
