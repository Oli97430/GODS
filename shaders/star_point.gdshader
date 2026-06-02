shader_type spatial;
// Point lumineux d'étoile, mobile-friendly : billboard additif non éclairé.
// Compatible MultiMeshInstance3D (couleur + custom data par instance).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Taille apparente des points (fraction de la distance caméra => taille écran ~constante).
uniform float point_screen_scale = 0.01;

// INSTANCE_CUSTOM n'existe qu'en vertex : on relaie le flag de surlignage au fragment.
varying float v_highlight;

void vertex() {
	v_highlight = INSTANCE_CUSTOM.r;                  // 1.0 si le système est sélectionné
	float type_size = max(INSTANCE_CUSTOM.g, 0.001);  // multiplicateur de taille selon le type

	// Centre de l'instance en espace vue (MODEL_MATRIX inclut la transform de la galaxie).
	vec4 center_view = VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float dist = max(-center_view.z, 0.001);

	// Taille proportionnelle à la distance => le point garde une taille ~constante à
	// l'écran quel que soit le zoom (bureau) ou l'échelle de l'hologramme (XR).
	float size = point_screen_scale * dist * type_size * mix(1.0, 2.4, v_highlight);

	// Quad face caméra (billboard).
	vec2 q = VERTEX.xy * size;
	center_view.xyz += vec3(q, 0.0);
	POSITION = PROJECTION_MATRIX * center_view;
}

void fragment() {
	// Dégradé radial doux : cœur dense + halo diffus.
	vec2 d = UV * 2.0 - 1.0;
	float dist2 = dot(d, d);
	float glow = clamp(1.0 - dist2, 0.0, 1.0);
	float core = pow(glow, 3.0);

	ALBEDO = COLOR.rgb * mix(1.0, 2.0, v_highlight);
	ALPHA = clamp(core + glow * 0.25, 0.0, 1.0);
}
