shader_type spatial;
render_mode cull_back;
// Lune (phase 14) : reprend les couleurs de biome bakées par PlanetGenerator mais les DÉSATURE
// et les teinte en rocheux/sec (pas d'océan, pas de végétation visible). Éclairée par les
// lumières de la scène (la directionnelle = l'étoile) => phases lunaires correctes gratuitement.

uniform vec3 rock_tint : source_color = vec3(0.60, 0.55, 0.50);
uniform float desat = 0.80;

void fragment() {
	float l = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));   // luminance de la couleur de biome
	vec3 c = mix(COLOR.rgb, vec3(l), desat);               // désaturation
	ALBEDO = c * rock_tint * 1.5;                          // teinte rocheuse propre à la lune
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
