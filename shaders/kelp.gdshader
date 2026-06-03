shader_type spatial;
render_mode cull_disabled;
// Lame de kelp/algue : enracinée au fond (base UV.y=0 fixe), ONDULE de plus en plus vers le sommet
// (UV.y=1). Le balancement suit le TIME (courant lent) + un déphasage par instance (INSTANCE_CUSTOM.x) =>
// un même champ ondule ensemble mais pas synchrone. LIT + fog (les lames lointaines virent au bleu).
// ⚠️ INSTANCE_CUSTOM n'est lu qu'en vertex() (pas de varying nécessaire).

uniform vec3 kelp_col : source_color = vec3(0.10, 0.30, 0.18);   // vert-brun sombre
uniform float sway_speed = 1.3;
uniform float sway_amp = 0.35;   // m d'amplitude au sommet

void vertex() {
	float up = clamp(UV.y, 0.0, 1.0);            // 0 = base ancrée, 1 = sommet libre
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	VERTEX.x += up * up * sway_amp * sin(TIME * sway_speed + ph + up * 2.2);
	VERTEX.z += up * up * sway_amp * 0.4 * cos(TIME * sway_speed * 0.8 + ph);
}

void fragment() {
	ALBEDO = kelp_col;
	ROUGHNESS = 0.85;
}
