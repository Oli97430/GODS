shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;
// Onde de choc d'atterrissage de puissance : disque horizontal (PlaneMesh, normale +Y) avec un anneau de
// poussière qui s'étale + un voile central. ADDITIF. `alpha` piloté par le CPU (fondu sur la durée du burst).

uniform vec3 col : source_color = vec3(0.82, 0.79, 0.70);
uniform float alpha = 0.0;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;          // 0 centre -> 1 bord
	float ring = smoothstep(0.45, 0.72, r) * (1.0 - smoothstep(0.82, 1.0, r));
	float core = (1.0 - smoothstep(0.0, 0.85, r)) * 0.22;
	ALBEDO = col;
	ALPHA = (ring + core) * alpha;
}
