shader_type spatial;
// Eau de SURFACE (améliorée) : houle large (déplacement vertex) + ripples fins MULTI-OCTAVES sur les
// normales (=> scintillement à la surface), fresnel (reflet ciel aux bords), réflexion screen-space,
// spéculaire solaire SERRÉ (étincelles) + halo large — tous deux suivant sun_direction. Teinte
// profondeur -> turquoise peu profonde. Pensé pour le tonemap AgX + glow (les étincelles « bloom »).
// Passe transparente + depth_draw_opaque : SCREEN_TEXTURE contient la scène (terrain/ciel) à réfléchir.
render_mode blend_mix, depth_draw_opaque, cull_disabled;   // cull_disabled : dessous visible en nageant (vu d'en haut = identique, mêmes triangles)

uniform vec4 water_color : source_color = vec4(0.04, 0.22, 0.38, 1.0);
uniform vec3 sky_tint : source_color = vec3(0.5, 0.6, 0.8);
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);   // monde, VERS le soleil (maj chaque frame)
uniform float sun_up = 1.0;   // 0 = soleil sous l'horizon (nuit) -> 1 = haut ; coupe spéculaire + reflet de jour la nuit
uniform float planet_radius = 3000.0;
uniform float wave_time = 0.0;
uniform float wave_height = 0.12;
uniform float wave_scale = 0.15;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;   // profondeur scène (transparence + écume)
uniform float reflect_strength = 0.7;
uniform float reflect_dist = 25.0;
uniform float depth_fade = 3.0;      // m : faible => l'eau redevient opaque vite (corps opaque = pas de grille du fond ;
                                     //     seule la frange de rive translucide montre les bas-fonds)
uniform float foam_width = 0.5;      // m : largeur de la bande d'écume de rive
uniform float shallow_alpha = 0.25;  // opacité minimale en eau peu profonde (on voit le fond, surface encore lisible)

varying vec3 v_world;

// Houle large (déplacement vertex + base de la normale).
float swell(vec2 p, float t) {
	float w = sin(dot(p, vec2(0.6, 0.0)) + t * 1.1) * 0.50;
	w += sin(dot(p, vec2(0.3, 0.5)) + t * 0.9) * 0.35;
	w += sin(dot(p, vec2(-0.2, 0.7)) + t * 1.4) * 0.25;
	return w;
}

// Ripples fins (haute fréquence) : normales seulement => scintillement / facettes.
float ripple(vec2 p, float t) {
	float w = sin(dot(p, vec2(2.3, 1.7)) + t * 2.5) * 0.50;
	w += sin(dot(p, vec2(-1.9, 3.1)) + t * 3.2) * 0.32;
	w += sin(dot(p, vec2(4.7, -3.7)) + t * 4.1) * 0.20;
	return w;
}

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float drop = (wpos.x * wpos.x + wpos.z * wpos.z) / (2.0 * planet_radius);   // courbure de la mer
	float wv = swell(wpos.xz * wave_scale, wave_time) * wave_height;
	wpos.y += wv - drop;
	VERTEX.y += wv - drop;
	v_world = wpos;
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// Estompe les RIPPLES fins avec la DISTANCE : leurs hautes fréquences sous-échantillonnées au loin
	// créaient un moiré qui lit comme une "grille" sur l'océan / grands lacs. De près = détail complet.
	float ripple_fade = clamp(1.0 - (length(cam - v_world) - 25.0) / 160.0, 0.0, 1.0);
	// Normale = gradient(houle large) + gradient(ripples fins estompés au loin) => micro-relief animé.
	vec2 p = v_world.xz * wave_scale;
	vec2 pd = v_world.xz * wave_scale * 4.0;
	float e = 0.5;
	float bx = swell(p + vec2(e, 0.0), wave_time) - swell(p - vec2(e, 0.0), wave_time);
	float bz = swell(p + vec2(0.0, e), wave_time) - swell(p - vec2(0.0, e), wave_time);
	float dx = (ripple(pd + vec2(e, 0.0), wave_time) - ripple(pd - vec2(e, 0.0), wave_time)) * ripple_fade;
	float dz = (ripple(pd + vec2(0.0, e), wave_time) - ripple(pd - vec2(0.0, e), wave_time)) * ripple_fade;
	vec3 wn = normalize(vec3(-(bx * wave_height + dx * wave_height * 2.4), 1.0, -(bz * wave_height + dz * wave_height * 2.4)));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	vec3 vd = normalize(cam - v_world);
	float fres = pow(1.0 - clamp(dot(wn, vd), 0.0, 1.0), 4.0);

	// Réflexion screen-space (1 échantillon le long du rayon réfléchi) + repli teinte ciel.
	vec3 incident = normalize(VERTEX);
	vec3 refl_v = reflect(incident, NORMAL);
	vec3 rp = VERTEX + refl_v * reflect_dist;
	vec4 cp = PROJECTION_MATRIX * vec4(rp, 1.0);
	vec2 ruv = (cp.xy / cp.w) * 0.5 + 0.5;
	float on = step(0.001, cp.w) * step(0.0, ruv.x) * step(ruv.x, 1.0) * step(0.0, ruv.y) * step(ruv.y, 1.0);
	vec3 reflected = mix(sky_tint * (0.10 + 0.90 * sun_up), texture(screen_tex, ruv).rgb, on);   // repli ciel assombri la nuit

	// Profondeur d'eau RÉELLE (surface -> fond) via la depth texture (scène opaque déjà rendue).
	float scene_d = texture(depth_tex, SCREEN_UV).r;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_d, 1.0);
	// Garde : si pas de géométrie derrière (ciel, scene_d≈1) ou w≈0 => eau « profonde » (opaque), pas de frange aberrante.
	float water_depth = depth_fade;
	if (scene_d < 0.9999 && abs(vpos.w) > 1e-6) {
		water_depth = max(-(vpos.z / vpos.w) + VERTEX.z, 0.0);   // (fond) - (surface) en espace vue
	}
	float depth01 = clamp(water_depth / depth_fade, 0.0, 1.0);

	// Couleur : eau peu profonde (turquoise VIF) -> profonde (sombre), puis reflet ciel aux bords (fresnel).
	vec3 shallow = mix(water_color.rgb, vec3(0.14, 0.62, 0.66), 0.72);
	vec3 base = mix(shallow, water_color.rgb, depth01);
	ALBEDO = mix(base, reflected, clamp(fres * reflect_strength + 0.06, 0.0, 1.0));

	// Écume de rive : bande claire là où l'eau est très peu profonde, brisée par les ripples (pas de ligne nette).
	float foam_noise = 0.55 + 0.45 * sin(dot(v_world.xz, vec2(3.1, 2.7)) + wave_time * 3.0 + dx * 9.0);
	float foam = smoothstep(foam_width, 0.0, water_depth) * foam_noise;
	ALBEDO = mix(ALBEDO, vec3(0.93, 0.96, 0.98), foam);

	// Transparence : translucide en eau peu profonde (on voit le fond), opaque en profondeur ; écume opacifie.
	ALPHA = clamp(mix(shallow_alpha, 1.0, depth01) + foam, 0.0, 1.0);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.03, 0.16, fres);
	SPECULAR = 0.9;

	// Spéculaire solaire : étincelle serrée (bloom via glow) + halo large, suit sun_direction.
	vec3 sg = reflect(-vd, wn);
	float sd = max(dot(sg, normalize(sun_direction)), 0.0);
	float glint = pow(sd, 180.0) * 2.6;   // exposant réduit : étincelle moins « 1 pixel » => moins de flicker stéréo
	float sheen = pow(sd, 22.0) * 0.45;
	// Étincelle chaude au ras de l'horizon, blanche en plein jour ; ÉTEINTE quand le soleil est couché (sun_up).
	vec3 glint_col = mix(vec3(1.0, 0.52, 0.22), vec3(1.0, 0.96, 0.84), sun_up);
	EMISSION = glint_col * (glint + sheen) * sun_up;
}
