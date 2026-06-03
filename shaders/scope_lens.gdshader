shader_type spatial;
// Verre de lunette VR : affiche le rendu du SubViewport-loupe (vue grossie de l'axe de visée), masqué en
// DISQUE (coins jetés => optique ronde), avec réticule (croix + point, couleur de l'arme) et assombrissement
// progressif vers le bord (corps de lunette). Unshaded => brille comme une optique, indépendant de la lumière.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D scope_tex : source_color, filter_linear;
uniform vec4 reticle_color : source_color = vec4(0.45, 1.0, 0.55, 1.0);
uniform float rim = 0.84;        // rayon (0..1) où commence l'assombrissement du tube

void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;          // 0 au centre, 1 au bord du quad
	if (r > 1.0) {
		discard;                         // hors du cercle => verre rond (pas de carré noir)
	}
	vec3 view = texture(scope_tex, UV).rgb;
	// Réticule : croix fine (avec coupure centrale) + point central, à la couleur du projectile.
	float ax = abs(c.x);
	float ay = abs(c.y);
	float line_h = (1.0 - smoothstep(0.0, 0.006, ay)) * step(0.05, ax) * step(ax, 0.42);
	float line_v = (1.0 - smoothstep(0.0, 0.006, ax)) * step(0.05, ay) * step(ay, 0.42);
	float dot = 1.0 - smoothstep(0.012, 0.02, length(c));
	float ret = clamp(line_h + line_v + dot, 0.0, 1.0);
	vec3 col = mix(view, reticle_color.rgb, ret);
	// Corps de lunette : assombrissement progressif vers le bord.
	col *= 1.0 - smoothstep(rim, 1.0, r) * 0.95;
	ALBEDO = col;
}
