shader_type spatial;
render_mode cull_disabled, shadows_disabled, specular_disabled;
// Cascade (phase 23) : nappe VERTICALE d'eau qui chute. Stries de mousse défilant vers le BAS, blanches,
// semi-transparentes, écume plus lumineuse. Animée par TIME. UV poussés par SurfaceGenerator :
//   UV.x = largeur en MÈTRES, UV.y = hauteur en MÈTRES (0 en haut, croît vers le bas).
// => taille de stries cohérente quelle que soit la dimension de la chute. Pas de POSITION nécessaire.

uniform vec3 water_tint : source_color = vec3(0.72, 0.86, 0.97);   // teinte de l'eau (hors écume)
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);      // écume
uniform float fall_speed = 4.0;      // m/s de défilement vertical des stries
uniform float opacity = 0.9;

float h11(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h11(i);
	float b = h11(i + vec2(1.0, 0.0));
	float c = h11(i + vec2(0.0, 1.0));
	float d = h11(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float u = UV.x;
	float yfall = UV.y + TIME * fall_speed;                 // hauteur défilant vers le bas
	// Colonnes d'eau : bruit étiré verticalement (stries fines en largeur, longues en hauteur).
	float n1 = vnoise(vec2(u * 2.0, yfall * 0.45));
	float n2 = vnoise(vec2(u * 6.5 + 3.0, yfall * 1.25));
	float foam = smoothstep(0.42, 0.85, n1 * 0.6 + n2 * 0.4);
	// Lèvre (haut) plus blanche : l'eau se déchire en tombant.
	float lip = 1.0 - smoothstep(0.0, 1.2, UV.y);
	foam = clamp(foam + lip * 0.5, 0.0, 1.0);
	ALBEDO = mix(water_tint, foam_color, foam);
	ALPHA = opacity * (0.55 + 0.45 * foam);
	ROUGHNESS = 0.35;
	METALLIC = 0.0;
	EMISSION = vec3(0.85, 0.92, 1.0) * foam * 0.22;          // léger éclat d'écume (joue avec le glow)
}
