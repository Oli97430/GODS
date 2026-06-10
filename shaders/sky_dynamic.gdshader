shader_type sky;
render_mode use_debanding;
// Ciel dynamique jour/nuit (phase 12 + nuages procéduraux). Gradient horizon<->zénith fonction de
// l'altitude du soleil, teinté par la couleur d'atmosphère ; lueur de crépuscule ; disque + halo du
// soleil ; NUAGES procéduraux (fbm projeté sur le dôme, dérive lente, éclairés par le soleil,
// occultant le soleil quand denses) dont la densité suit cloud_coverage (météo). Une seule source de
// temps : SkyManager pousse sun_dir (direction VERS le soleil, repère monde surface, +Y up).

uniform vec3 sun_dir = vec3(0.0, 0.3, 0.95);          // vers le soleil (monde)
uniform vec3 atmo_tint : source_color = vec3(0.4, 0.6, 0.9);
uniform vec3 day_zenith : source_color = vec3(0.16, 0.40, 0.78);
uniform vec3 day_horizon : source_color = vec3(0.62, 0.76, 0.92);
uniform vec3 dusk_color : source_color = vec3(0.98, 0.46, 0.20);
uniform vec3 night_zenith : source_color = vec3(0.010, 0.020, 0.055);
uniform vec3 night_horizon : source_color = vec3(0.035, 0.050, 0.115);
uniform vec3 ground_color : source_color = vec3(0.020, 0.020, 0.030);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_size = 0.032;   // 1 - cos(rayon angulaire) du disque (un peu plus gros = soleil net)
uniform float sun_glow = 8.0;     // serrage du halo autour du disque (plus bas = halo plus large)
uniform float cloud_coverage = 0.0;   // météo (phase 13) : 0 dégagé -> 1 couvert
uniform float lightning = 0.0;        // météo : flash d'éclair (0..1) blanchit brièvement le ciel
uniform float cloud_speed = 0.006;    // dérive des nuages (vitesse)

// --- Aurores boréales (confort/variété) : rideaux NOCTURNES animés. Présence + teintes poussées par
// SkyManager (déterministes par seed planète) => certaines planètes en ont, d'autres non.
uniform float aurora_strength = 0.0;                                 // 0 = aucune aurore sur cette planète
uniform vec3 aurora_color : source_color = vec3(0.12, 1.0, 0.45);    // teinte BASSE du rideau (vert classique)
uniform vec3 aurora_color2 : source_color = vec3(0.25, 0.55, 1.0);   // teinte HAUTE du rideau (bleu/violet)

// --- Nuages VOLUMÉTRIQUES (raymarching d'une dalle d'altitude, vrai relief + éclairage) ---
uniform float clouds_on = 1.0;        // 0 = désactivés (escape perf, lié au toggle atmosphère)
uniform float cloud_base = 650.0;     // altitude (Y monde) de la base de la couche
uniform float cloud_top = 1300.0;     // altitude du sommet
uniform float cloud_scale = 0.0016;   // échelle du bruit 3D (plus petit = nuages plus gros)
uniform float cloud_absorb = 0.05;    // densité optique (opacité par mètre traversé)
uniform float cloud_march_dist = 6000.0;  // distance max de marche (anti-explosion à l'horizon)

// --- Bruit valeur + fbm (nuages procéduraux, sans texture) ---
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));   // rotation+scale : casse l'alignement des octaves
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = m * p;
		a *= 0.5;
	}
	return v;
}

// --- Bruit 3D + densité de nuage (raymarching volumétrique) ---
float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
	           mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}
float fbm3_hi(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise3(p); p *= 2.03; a *= 0.5; }
	return v;
}
float fbm3_lo(vec3 p) {
	float v = 0.0;
	float a = 0.6;
	for (int i = 0; i < 2; i++) { v += a * vnoise3(p); p *= 2.5; a *= 0.5; }
	return v;
}
vec3 cloud_drift() { return vec3(TIME * cloud_speed * 8.0, 0.0, TIME * cloud_speed * 5.0); }
// Profil de la couche : gradient d'altitude (base plate, sommet bombé) × seuil de couverture météo.
float cloud_shape(float n, float y) {
	float h = clamp((y - cloud_base) / max(cloud_top - cloud_base, 1.0), 0.0, 1.0);
	float grad = smoothstep(0.0, 0.22, h) * (1.0 - smoothstep(0.55, 1.0, h));
	// Seuil par temps clair => nuages cumulus DISTINCTS avec ciel bleu entre eux (toujours quelques nuages,
	// jamais un ciel vide) ; descend si couvert (météo) jusqu'à un vrai ciel bouché.
	float cov = mix(0.46, 0.26, cloud_coverage);
	return smoothstep(cov, cov + 0.20, n) * grad;
}
float cloud_dense_hi(vec3 wp) { return cloud_shape(fbm3_hi(wp * cloud_scale + cloud_drift()), wp.y); }
float cloud_dense_lo(vec3 wp) { return cloud_shape(fbm3_lo(wp * cloud_scale + cloud_drift()), wp.y); }

void sky() {
	float up = EYEDIR.y;                 // 1 zénith, 0 horizon, <0 sous l'horizon
	float sun_alt = sun_dir.y;           // sin(altitude) du soleil
	float day = smoothstep(-0.18, 0.22, sun_alt);   // 0 nuit -> 1 jour

	// Teintes de jour modulées par l'atmosphère propre à la planète.
	vec3 z_day = mix(day_zenith, atmo_tint * 0.7, 0.5);
	vec3 h_day = mix(day_horizon, atmo_tint, 0.4);

	// Gradient vertical zénith<->horizon, séparément jour et nuit, puis fondu par 'day'.
	float t = smoothstep(0.0, 0.45, up);
	vec3 day_col = mix(h_day, z_day, t);
	vec3 night_col = mix(night_horizon, night_zenith, t);
	vec3 col = mix(night_col, day_col, day);

	// Lueur de crépuscule (maxi quand le soleil rase l'horizon, près de l'horizon, vers l'azimut soleil).
	float horizon_band = 1.0 - smoothstep(0.0, 0.30, abs(up));
	float twilight = smoothstep(0.0, 0.18, sun_alt + 0.18) * (1.0 - smoothstep(0.0, 0.36, sun_alt));
	vec3 eye_h = normalize(vec3(EYEDIR.x, 0.0, EYEDIR.z) + vec3(0.0001));
	vec3 sun_h = normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + vec3(0.0001));
	float toward = max(dot(eye_h, sun_h), 0.0);
	col = mix(col, dusk_color, clamp(horizon_band * twilight * (0.35 + 0.65 * toward), 0.0, 1.0));

	// Sol sombre sous l'horizon.
	col = mix(col, ground_color, smoothstep(0.0, -0.08, up));

	// Couverture nuageuse (météo) : léger assombrissement/désaturation global du ciel quand couvert.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 overcast = mix(col, vec3(lum), 0.7) * 0.66;
	col = mix(col, overcast, cloud_coverage * 0.55);

	// Disque + halo du soleil : disque vif + grand halo lumineux => soleil bien visible (jour, et au ras de
	// l'horizon au lever/coucher où max(day,..) maintient sa présence).
	float dsun = dot(EYEDIR, normalize(sun_dir));
	float disk = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.4, dsun);
	float glow = pow(max(dsun, 0.0), sun_glow);
	float halo = pow(max(dsun, 0.0), 2.2);   // grand halo doux autour du soleil
	col += sun_color * (disk * 10.0 + glow * 1.1 + halo * 0.25) * max(day, 0.18) * (1.0 - cloud_coverage * 0.55);

	// --- NUAGES VOLUMÉTRIQUES (projection DIRECTIONNELLE, sans POSITION — robuste en shader de ciel) ---
	// On échantillonne le bruit 3D le long de EYEDIR à des HAUTEURS de couche successives (origine caméra
	// implicite ≈ 0) : volume + bords doux + éclairage par marche vers le soleil. POSITION n'est pas fiable
	// dans les passes de ciel (radiance/cubemap) ; cette forme s'en passe.
	if (clouds_on > 0.5 && EYEDIR.y > 0.06) {
		const int STEPS = 12;
		const int LSTEPS = 2;
		float dy = (cloud_top - cloud_base) / float(STEPS);
		vec2 ratio = EYEDIR.xz / EYEDIR.y;          // décalage horizontal par unité de hauteur
		float seg = dy / EYEDIR.y;                   // longueur de segment le long du rayon (épaisseur optique)
		vec3 sdir = normalize(sun_dir);
		vec3 sun_lit = sun_color * (0.6 + 0.7 * day);
		vec3 amb = mix(vec3(0.22, 0.25, 0.32), col, 0.4) * (0.46 + 0.54 * day);   // nuages encore visibles la nuit
		float trans = 1.0;
		vec3 acc = vec3(0.0);
		for (int i = 0; i < STEPS; i++) {
			if (trans < 0.03) { break; }
			float yy = cloud_base + dy * (float(i) + 0.5);
			vec3 wp = vec3(ratio.x * yy, yy, ratio.y * yy);
			float d = cloud_dense_hi(wp);
			if (d > 0.001) {
				float dl = cloud_dense_lo(wp + sdir * 220.0) + cloud_dense_lo(wp + sdir * 520.0);
				float sun_t = exp(-dl * 260.0 * cloud_absorb * 1.4);   // Beer : lumière restante vers le soleil
				vec3 lit = amb + sun_lit * sun_t;
				float alpha = 1.0 - exp(-d * seg * cloud_absorb);
				acc += trans * alpha * lit;                            // composite avant->arrière
				trans *= 1.0 - alpha;
			}
		}
		float fade = smoothstep(0.06, 0.20, EYEDIR.y);   // fondu doux près de l'horizon (anti-aliasing)
		col = acc * fade + col * (trans * fade + (1.0 - fade));
	}

	// --- AURORES BORÉALES (nuit + ciel dégagé) : rideaux animés, additifs, variété par planète ---
	// Vivent dans une bande d'altitude (ni horizon ni zénith). 'wave' = serpentement lent du rideau ;
	// 'stri' = plis verticaux fins. Dégradé bas->haut entre les deux teintes. Cachées le jour et sous
	// les nuages. fbm() est déjà défini plus haut (nuages procéduraux).
	if (aurora_strength > 0.001) {
		float night = 1.0 - day;
		float clear = 1.0 - cloud_coverage;
		float band = smoothstep(0.04, 0.32, up) * (1.0 - smoothstep(0.55, 0.96, up));
		float vis = band * night * clear;
		if (vis > 0.001) {
			float az = atan(EYEDIR.x, EYEDIR.z);                    // azimut -pi..pi
			float t = TIME * 0.045;
			float wave = fbm(vec2(az * 1.7 + t, up * 2.2));         // serpente lentement
			float stri = fbm(vec2(az * 11.0 - t * 2.3, up * 1.5));  // plis verticaux fins
			float curtain = smoothstep(0.42, 0.78, wave) * (0.45 + 0.55 * stri);
			vec3 acol = mix(aurora_color, aurora_color2, smoothstep(0.08, 0.62, up));
			col += acol * curtain * vis * aurora_strength * 0.8;
		}
	}

	// Éclair : blanchiment global bref du ciel (météo, phase 13).
	col = mix(col, vec3(1.05), clamp(lightning * 0.7, 0.0, 1.0));

	COLOR = col;
}
