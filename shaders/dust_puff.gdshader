shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled, specular_disabled;
// Dôme de poussière d'atterrissage de puissance : translucide, bords plus denses (fresnel) => lecture
// volumétrique douce d'un nuage de poussière qui s'étale + s'élève. blend_mix (occulte/teinte le fond,
// pas additif comme un flash). `alpha` piloté par le CPU (fondu sur la durée du burst).

uniform vec3 col : source_color = vec3(0.60, 0.56, 0.48);
uniform float alpha = 0.0;

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.4);
	ALBEDO = col;
	ALPHA = (0.16 + 0.5 * f) * alpha;   // silhouette plus dense (poussière au pourtour)
	ROUGHNESS = 1.0;
}
