// Occlusion du DÔME CÉLESTE (étoiles, galaxies, lunes) par la COUCHE DE NUAGES de sky_dynamic.
// Les nuages sont rendus dans la passe de CIEL (fond) : ils ne peuvent donc PAS occulter la géométrie du
// dôme (étoiles/lunes au rayon 3000) via le depth → le dôme s'affichait toujours DEVANT les nuages.
// On recalcule ici la TRANSMITTANCE des nuages le long de la direction MONDE de l'objet (même champ de
// bruit + mêmes paramètres que sky_dynamic, poussés en uniformes GLOBAUX par SkyManager) pour estomper
// l'objet là où un nuage passe devant. Inclus par starfield/galaxy/surface_moon.

global uniform float cloud_coverage_g;   // météo (0 dégagé → 1 couvert) — = SkyManager
global uniform float clouds_on_g;        // 0 = nuages off (toggle atmosphère)
global uniform float cloud_base_g;       // altitude base de la couche (Y monde)
global uniform float cloud_top_g;        // altitude sommet
global uniform float cloud_scale_g;      // échelle du bruit 3D
global uniform float cloud_absorb_g;     // densité optique
global uniform float cloud_speed_g;      // dérive (doit matcher sky_dynamic pour aligner les nuages)

float co_hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}
float co_vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = co_hash13(i);
	float n100 = co_hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = co_hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = co_hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = co_hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = co_hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = co_hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = co_hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
	           mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}
// 3 octaves (silhouette d'occlusion ; sky_dynamic en utilise 4 pour le rendu fin) — proche, moins cher.
float co_fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) { v += a * co_vnoise3(p); p *= 2.03; a *= 0.5; }
	return v;
}
vec3 co_drift() { return vec3(TIME * cloud_speed_g * 8.0, 0.0, TIME * cloud_speed_g * 5.0); }
// Profil de couche IDENTIQUE à sky_dynamic.cloud_shape (mêmes seuils => mêmes nuages).
float co_shape(float n, float y) {
	float h = clamp((y - cloud_base_g) / max(cloud_top_g - cloud_base_g, 1.0), 0.0, 1.0);
	float grad = smoothstep(0.0, 0.22, h) * (1.0 - smoothstep(0.55, 1.0, h));
	float cov = mix(0.46, 0.26, cloud_coverage_g);
	return smoothstep(cov, cov + 0.20, n) * grad;
}
// Transmittance des nuages [0..1] le long de la direction MONDE 'dir' (1 = dégagé, 0 = nuage opaque).
// Marche la même dalle d'altitude que sky_dynamic (origine observateur ≈ monde 0, garanti par l'origine
// flottante qui garde le joueur près de 0). Estompée près de l'horizon comme le ciel (anti-aliasing).
float cloud_transmittance(vec3 dir) {
	if (clouds_on_g < 0.5 || dir.y <= 0.06) { return 1.0; }
	const int STEPS = 6;
	float dy = (cloud_top_g - cloud_base_g) / float(STEPS);
	vec2 ratio = dir.xz / dir.y;
	float seg = dy / dir.y;
	float trans = 1.0;
	for (int i = 0; i < STEPS; i++) {
		if (trans < 0.05) { break; }
		float yy = cloud_base_g + dy * (float(i) + 0.5);
		vec3 wp = vec3(ratio.x * yy, yy, ratio.y * yy);
		float d = co_shape(co_fbm3(wp * cloud_scale_g + co_drift()), yy);
		if (d > 0.001) {
			float alpha = 1.0 - exp(-d * seg * cloud_absorb_g);
			trans *= 1.0 - alpha;
		}
	}
	float fade = smoothstep(0.06, 0.20, dir.y);
	return mix(1.0, trans, fade);
}
