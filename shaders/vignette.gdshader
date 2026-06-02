shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Vignette de CONFORT VR : sphère inversée tête-bloquée. Transparente dans un CÔNE avant (vision libre),
// sombre au-delà ; le cône se RESSERRE avec `amount` (piloté par la vitesse) => tunnel-vision qui réduit
// le flux périphérique = anti-nausée (vection). Rendue sur la face INTÉRIEURE (cull_front), toujours
// devant (depth_test_disabled). Marche en stéréo (centrée sur l'avant de la tête).

uniform float amount = 0.0;   // 0 = aucune vignette, 1 = très resserrée

void fragment() {
	float ang = acos(clamp(-normalize(VERTEX).z, -1.0, 1.0));   // angle depuis l'avant (-Z local), en radians
	float open = mix(2.4, 0.55, amount);                        // demi-angle du cône clair : large -> serré
	ALBEDO = vec3(0.0);
	ALPHA = smoothstep(open, open + 0.4, ang) * clamp(amount * 1.6, 0.0, 0.92);
}
