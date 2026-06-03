shader_type spatial;
// Vent léger pour la végétation (arbres + herbe). Balancement de VERTEX ancré à la base
// (y=0) et croissant avec la hauteur => le tronc/la base ne bougent pas, le sommet oscille.
// Couleur = couleurs de vertices du mesh (biome). Mobile-friendly (lambert, sans spéculaire,
// double face pour l'herbe/feuillage). wind_strength = 0 => vent désactivé (statique).
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float wind_strength : hint_range(0.0, 0.3) = 0.04;
uniform float wind_speed = 1.5;
uniform float wind_scale = 0.12;   // variation spatiale de la phase (par mètre monde)

// Bioluminescence (vie nocturne) : pilotée par SurfaceView (= force biolum de la planète × facteur nuit).
// GLOBAL uniform => une seule valeur pour toute la végétation. À 0 (jour OU planète non-biolum) =>
// EMISSION = 0 => rendu STRICTEMENT identique (zéro régression). > 0 la nuit => la flore émet sa couleur.
global uniform float biolum_glow;

// Teinte par instance (phase 24) : INSTANCE_CUSTOM.rgb si fournie (alpha>0.5) => variété de forêt.
// Les meshes SANS custom data (herbe) ont INSTANCE_CUSTOM=0 => alpha<0.5 => teinte neutre (jamais noir).
varying vec3 v_tint;

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;       // position monde (inclut l'instance MultiMesh)
	float ph = TIME * wind_speed + (wpos.x + wpos.z) * wind_scale;
	float amp = wind_strength * max(VERTEX.y, 0.0);            // amplitude ~ hauteur locale
	VERTEX.x += sin(ph) * amp;
	VERTEX.z += cos(ph * 0.8) * amp * 0.6;
	v_tint = (INSTANCE_CUSTOM.a > 0.5) ? INSTANCE_CUSTOM.rgb : vec3(1.0);
}

void fragment() {
	ALBEDO = COLOR.rgb * v_tint;   // couleur de vertex (biome) × teinte d'instance
	ROUGHNESS = 1.0;
	EMISSION = ALBEDO * biolum_glow;   // bioluminescence nocturne : la flore émet sa couleur (0 le jour / hors planète biolum => no-op)
}
