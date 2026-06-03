shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_schlick_ggx;
// Bulle sous-marine : petite sphère translucide avec un RIM fresnel lumineux (le contour brille, le centre
// est presque transparent => lecture "bulle"). Soumise au fog (les bulles lointaines se fondent). Très cheap.

uniform vec3 tint : source_color = vec3(0.75, 0.88, 0.96);

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	ALBEDO = tint;
	ALPHA = 0.10 + 0.55 * f;   // rim lumineux (effet bulle)
	ROUGHNESS = 0.05;
}
