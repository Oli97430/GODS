shader_type spatial;
render_mode cull_disabled, depth_draw_never, blend_add, unshaded, shadows_disabled, fog_disabled;
// Bouclier d'énergie (façon Space Pirate Trainer) : panneau TRANSLUCIDE — RIM fresnel lumineux (contour qui
// brille fort), grille hexagonale/quadrillée ténue, teinte cyan, pulsation lente. ADDITIF (lueur). L'intérieur
// est presque transparent (on voit à travers), le pourtour et les lignes brillent.

uniform vec3 shield_col : source_color = vec3(0.3, 0.7, 1.0);
uniform float grid_scale = 13.0;
uniform float hit_flash = 0.0;   // 0..1 : flash bref quand le bouclier intercepte un tir (piloté par Shield.gd)

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);   // contour brillant
	vec2 g = abs(fract(UV * grid_scale) - 0.5);
	float line = smoothstep(0.42, 0.5, max(g.x, g.y));                                        // grille
	float pulse = 0.82 + 0.18 * sin(TIME * 2.2);
	// Flash d'interception : surface entière s'illumine brièvement (blanc bleuté).
	vec3 col = mix(shield_col, vec3(0.85, 0.95, 1.0), hit_flash);
	ALBEDO = col;
	ALPHA = clamp((0.05 + fres * 0.7 + line * 0.14) * pulse + hit_flash * 0.5, 0.0, 0.95);
}
