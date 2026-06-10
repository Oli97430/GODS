shader_type spatial;
// Surface de planète vue d'ORBITE — rendu ENRICHI (amélioration « très large » des visuels).
// Non éclairé : la lumière est calculée à la main (cohérent avec océan/atmosphère/nuages, stéréo stable).
//  • RELIEF DE DÉTAIL par perturbation de normale — gradient d'un fbm échantillonné en espace OBJET
//    (donc collé à la surface qui tourne) => montagnes/vallées qui accrochent la lumière : la planète
//    n'est plus « plate ».
//  • Terminateur DOUX (wrap) + bande CHAUDE de lever/coucher sur les terres.
//  • Côté nuit TEINTÉ (pas noir pur).
//  • Diffusion atmosphérique au LIMBE (le bord de la planète se fond dans son atmosphère).
//  • Léger spéculaire sur les zones CLAIRES (glace / littoral / désert) côté jour.
// Albédo de base = COULEUR DE VERTEX (biome) => déterminisme intact (aucune dépendance au mesh).
render_mode unshaded, cull_back;

uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);             // monde, VERS le soleil
uniform vec3 atmo_color : source_color = vec3(0.35, 0.55, 1.0);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.45, 0.22);
uniform vec3 night_tint : source_color = vec3(0.04, 0.06, 0.12);
uniform float detail_amp : hint_range(0.0, 2.0) = 0.85;       // force du relief de détail (0 = lisse)
uniform float detail_scale = 24.0;                            // fréquence du relief
uniform float ambient : hint_range(0.0, 0.5) = 0.07;         // remplissage (les pentes à l'ombre ne sont pas noires)
uniform float scatter_strength : hint_range(0.0, 1.5) = 0.65; // intensité du halo atmosphérique au limbe
uniform float specular_strength : hint_range(0.0, 1.0) = 0.22;
uniform float night_floor : hint_range(0.0, 0.3) = 0.035;
uniform float sun_intensity : hint_range(0.5, 2.5) = 1.35;   // luminosité du côté jour (≥ ancien light_energy)

varying vec3 v_world_normal;
varying vec3 v_local_dir;   // direction OBJET (stable sur la surface qui tourne) -> coord du bruit
varying vec3 v_t1w;         // tangentes MONDE (= tangentes objet tournées) -> transfert du gradient
varying vec3 v_t2w;

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

// fbm 3 octaves — relief de détail (assez riche, coût maîtrisé : 3 octaves × 3 prélèvements).
float fbm(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03) * 0.30 + vnoise(p * 4.07) * 0.15;
}

// Repère tangent OBJET stable pour une direction d (sur la sphère). Bascule l'axe de référence BIEN
// avant les pôles (0.95) pour garder des tangentes amples => gradient du bump précis, pas d'artefact polaire.
void obj_tangents(vec3 d, out vec3 t1, out vec3 t2) {
	vec3 up = abs(d.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	t1 = normalize(cross(up, d));
	t2 = cross(d, t1);
}

void vertex() {
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 d = normalize(VERTEX);
	v_local_dir = d;
	vec3 t1o;
	vec3 t2o;
	obj_tangents(d, t1o, t2o);
	// Tangentes objet -> monde via la rotation du modèle (calculée ici où MODEL_MATRIX est sûr).
	v_t1w = (MODEL_MATRIX * vec4(t1o, 0.0)).xyz;
	v_t2w = (MODEL_MATRIX * vec4(t2o, 0.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 Nw = normalize(v_world_normal);
	vec3 sd = normalize(sun_direction);

	// --- Relief de détail : gradient du fbm en espace OBJET -> bump de la normale MONDE ---
	vec3 d = normalize(v_local_dir);
	vec3 t1o;
	vec3 t2o;
	obj_tangents(d, t1o, t2o);
	float eps = 0.004;
	float h0 = fbm(d * detail_scale);
	float h1 = fbm((d + t1o * eps) * detail_scale);
	float h2 = fbm((d + t2o * eps) * detail_scale);
	vec2 grad = vec2(h1 - h0, h2 - h0) / eps;
	vec3 bump = -(grad.x * normalize(v_t1w) + grad.y * normalize(v_t2w)) * detail_amp * 0.02;
	bump = clamp(bump, vec3(-0.7), vec3(0.7));   // garde-fou : la normale ne s'inverse jamais
	vec3 Np = normalize(Nw + bump);

	// --- Jour / nuit ---
	float lit_base = dot(Nw, sd);                          // terminateur large (normale géométrique)
	float ndl = dot(Np, sd);                               // éclairage du relief de détail
	float day = smoothstep(-0.12, 0.22, lit_base);          // transition douce
	float diff = clamp((ndl + 0.15) / 1.15, 0.0, 1.0) * day; // diffus enroulé : terminateur doux + relief

	// --- Bande chaude au terminateur (lever / coucher) sur les terres ---
	float term = smoothstep(0.26, 0.0, abs(lit_base));
	base = mix(base, base * sunset_color * 1.4, term * 0.5);

	// --- Couleur de surface : ambiant + diffus (côté jour vif, au moins aussi clair qu'avant) ---
	vec3 sun_col = vec3(1.0, 0.97, 0.92) * sun_intensity;
	vec3 col = base * (ambient + diff * sun_col);

	// --- Côté nuit : teinte résiduelle (jamais noir pur) ---
	float night = 1.0 - day;
	col += (night_tint + base * night_floor) * night;

	// --- Spéculaire doux sur les zones CLAIRES (glace / littoral / désert), côté jour ---
	float bright = clamp((base.r + base.g + base.b) / 3.0, 0.0, 1.0);
	vec3 vieww = normalize((INV_VIEW_MATRIX * vec4(normalize(VIEW), 0.0)).xyz);
	vec3 refl = reflect(-vieww, Np);
	float spec = pow(max(dot(refl, sd), 0.0), 40.0) * specular_strength * day * smoothstep(0.45, 0.95, bright);
	col += sun_col * spec;

	// --- Diffusion atmosphérique au LIMBE (fresnel espace vue) : le bord se fond dans l'atmosphère ---
	float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndotv, 3.0);
	float scatter = fres * scatter_strength * mix(0.22, 1.0, day);   // plus fort côté éclairé (avant-diffusion)
	col = mix(col, atmo_color, clamp(scatter, 0.0, 0.85));

	ALBEDO = col;
}
