shader_type spatial;
// Couche de nuages orbitale (améliorée) : couverture par fbm échantillonné sur la DIRECTION 3D du
// vertex (pas de couture UV), DOMAIN-WARP 3D => bandes / tourbillons (systèmes météo vus de l'espace),
// cœurs denses (masses opaques) + bords wispy, liseré éclairé côté soleil, ombrage jour/nuit +
// terminateur chaud. Défilement propre via cloud_speed. Non éclairé, alpha-blend.
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform float coverage : hint_range(0.0, 1.0) = 0.5; // 0 = ciel clair, 1 = couvert
uniform float cloud_speed = 0.02;                    // vitesse de défilement (propre)
uniform vec3 cloud_offset = vec3(0.0);               // décalage dérivé du seed (motif unique)
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform float night_floor : hint_range(0.0, 1.0) = 0.25;
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);    // direction VERS le soleil (monde)
uniform float cloud_scale = 3.0;                     // échelle de base du bruit
uniform float warp_amp = 0.40;                       // amplitude du domain-warp (bandes/tourbillons)

varying vec3 v_sample_dir;
varying vec3 v_world_normal;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// fbm 2 octaves (pour le warp, peu coûteux) et 4 octaves (détail des nuages).
float fbm2(vec3 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.1) * 0.4;
}
float fbm4(vec3 p) {
	return vnoise(p) * 0.50 + vnoise(p * 2.0) * 0.27 + vnoise(p * 4.1) * 0.15 + vnoise(p * 8.3) * 0.08;
}

void vertex() {
	// Direction objet tournée autour de Y => défilement des nuages à vitesse propre.
	float a = TIME * cloud_speed;
	float ca = cos(a);
	float sa = sin(a);
	vec3 d = normalize(VERTEX);
	v_sample_dir = vec3(ca * d.x - sa * d.z, d.y, sa * d.x + ca * d.z) + cloud_offset;
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 sp = v_sample_dir * cloud_scale;
	// Domain-warp 3D : décale l'échantillonnage par 3 fbm => bandes et tourbillons météo.
	vec3 w = vec3(fbm2(sp), fbm2(sp + vec3(7.3, 1.2, 3.4)), fbm2(sp + vec3(2.1, 8.7, 5.5)));
	float n = fbm4(sp + (w - 0.5) * warp_amp);

	float thr = 1.0 - coverage;
	float c = smoothstep(thr - 0.02, thr + 0.18, n);          // alpha : bords doux/wispy
	float core = smoothstep(thr + 0.10, thr + 0.32, n);       // cœurs denses : masses plus opaques
	c = clamp(c + core * 0.45, 0.0, 1.0);

	vec3 wn = normalize(v_world_normal);
	vec3 sd = normalize(sun_direction);
	float lit_s = dot(wn, sd);
	float lit = clamp(lit_s * 0.5 + 0.5, 0.0, 1.0);
	float shade = mix(night_floor, 1.0, lit);                 // nuages plus sombres côté nuit
	// Teinte chaude au TERMINATEUR (lever/coucher), cohérente avec l'atmosphère.
	float term = smoothstep(0.30, 0.0, abs(lit_s));
	vec3 col = mix(cloud_color, cloud_color * vec3(1.25, 0.72, 0.50), term * 0.55);
	// Liseré éclairé : bords (faible cœur) côté soleil plus brillants (diffusion vers l'avant approx.).
	float rim = pow(lit, 1.5) * (1.0 - core) * 0.30;
	ALBEDO = col * shade + cloud_color * rim;
	ALPHA = c;
}
