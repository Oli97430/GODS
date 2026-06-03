shader_type spatial;
render_mode cull_disabled;
// Poisson d'un banc : silhouette nageant avec ONDULATION de la queue — la partie arrière (-Z) oscille
// latéralement (X), la tête (+Z) reste. LIT (capte la lumière filtrée d'en haut) ET soumis au fog =>
// les poissons lointains se fondent dans le bleu sous-marin. INSTANCE_CUSTOM.x = phase d'ondulation (le
// banc n'est pas synchrone). ⚠️ INSTANCE_CUSTOM n'est utilisé qu'en vertex() (pas de varying nécessaire).

uniform vec3 body : source_color = vec3(0.55, 0.62, 0.72);   // argenté bleuté
uniform float wiggle_speed = 6.0;
uniform float wiggle_amp = 0.16;

void vertex() {
	float tail = clamp(-VERTEX.z + 0.1, 0.0, 1.0);   // 0 à la tête (+Z), ~1 vers la queue (-Z)
	VERTEX.x += tail * tail * wiggle_amp * sin(TIME * wiggle_speed + INSTANCE_CUSTOM.x * 6.2831);
}

void fragment() {
	ALBEDO = body;
	ROUGHNESS = 0.45;
	METALLIC = 0.15;
}
