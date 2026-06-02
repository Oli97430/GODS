shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Étoile filante : quad orienté le long du mouvement (orientation gérée par le node Starfield). Tête
// brillante (UV.x→1), traînée qui s'efface (UV.x→0), bord transversal doux (UV.y). Luminosité globale
// 'alpha' (vie de la météore × obscurité) poussée chaque frame par Starfield. Additif, ne s'occulte pas.

uniform float alpha = 0.0;

void fragment() {
	float head = UV.x * UV.x;                       // traînée -> tête concentrée
	float across = 1.0 - abs(UV.y - 0.5) * 2.0;     // 1 au centre, 0 aux bords (largeur)
	across = smoothstep(0.0, 1.0, across);
	ALBEDO = vec3(0.85, 0.92, 1.0);
	ALPHA = head * across * alpha;
}
