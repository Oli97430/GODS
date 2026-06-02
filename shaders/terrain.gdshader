shader_type spatial;
// Terrain : réplique StandardMaterial3D (albédo = COULEUR de vertex, roughness 1, normales du mesh) +
// GEOMORPHING. Chaque sommet porte en CUSTOM0 son déplacement (xyz, local) vers la forme du LOD plus
// GROSSIER ; le vertex shader l'applique selon `morph_factor` (instance uniform, PAR chunk), rampé juste
// avant le swap LOD => la forme fine épouse la grossière AVANT de basculer => plus de "pop".
// ⚠️ Les NORMALES (analytiques par halo, anti-couture) restent celles du mesh — non touchées.

instance uniform float morph_factor = 0.0;

void vertex() {
	VERTEX += CUSTOM0.xyz * morph_factor;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
