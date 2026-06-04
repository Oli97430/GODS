shader_type spatial;
// Décalque de CRATÈRE d'atterrissage de puissance, profil crédible : FOND sombre (brûlé) au centre →
// BOURRELET d'éjecta plus clair (terre retournée) vers r≈0.78 → retombée + RAYONS d'éjecta au-delà, le tout
// avec un BORD IRRÉGULIER (pas un disque parfait) et des FISSURES radiales. Posé au ras du sol (orienté à la
// pente). `fade` pilote l'apparition / disparition temporelle (alpha).
render_mode cull_disabled;

uniform vec4 floor_col : source_color = vec4(0.045, 0.038, 0.030, 1.0);   // fond du cratère (sombre, brûlé)
uniform vec4 rim_col : source_color = vec4(0.30, 0.24, 0.17, 1.0);        // bourrelet de terre retournée (clair)
uniform float fade = 1.0;

void fragment() {
	vec2 cc = UV - vec2(0.5);
	float ang = atan(cc.y, cc.x);
	float wob = 0.05 * (sin(ang * 7.0) + sin(ang * 13.0 + 1.7));   // bord irrégulier (déforme le rayon)
	float r = length(cc) * 2.0 / max(1.0 - wob, 0.6);             // 0 au centre, 1 au bord
	if (r > 1.0) {
		discard;
	}
	float rim = smoothstep(0.32, 0.78, r) * (1.0 - smoothstep(0.78, 1.0, r));   // anneau d'éjecta (bourrelet)
	float pit = 1.0 - smoothstep(0.0, 0.5, r);                                   // fond très sombre au centre
	vec3 col = mix(floor_col.rgb, rim_col.rgb, clamp(rim * 1.35, 0.0, 1.0));
	col *= 1.0 - pit * 0.5;
	float cracks = step(0.86, abs(sin(ang * 6.0 + 0.5))) * (1.0 - smoothstep(0.1, 0.7, r));
	col *= 1.0 - cracks * 0.5;                                                   // fissures radiales sombres
	float rays = step(0.72, abs(sin(ang * 9.0))) * smoothstep(0.78, 1.0, r) * 0.22;
	col += rim_col.rgb * rays;                                                   // rayons d'éjecta légers
	ALBEDO = col;
	ROUGHNESS = 1.0;
	ALPHA = fade * (1.0 - smoothstep(0.86, 1.0, r));                            // bord fondu + fondu temporel
}
