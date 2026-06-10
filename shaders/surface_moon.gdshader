shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled, fog_disabled;
// Lune vue depuis le SOL (phase 14) : disque/sphère sur la dôme du ciel. Éclairée par l'étoile
// via un lambert MANUEL (sun_local) — donc TOUJOURS éclairée, même la nuit où le soleil de
// scène (directionnelle) est éteint sous l'horizon. Phases correctes. fog_disabled (au-delà du
// brouillard). COLOR = couleur de biome bakée, désaturée en rocheux.
// blend_mix + depth_draw_opaque : la lune devient SEMI-transparente là où un nuage passe devant (la couche
// de nuages du ciel, dessinée derrière, transparaît) tout en écrivant le depth (occulte encore le dôme).
#include "res://shaders/cloud_occlusion.gdshaderinc"

uniform vec3 rock_tint : source_color = vec3(0.60, 0.55, 0.50);
uniform float desat = 0.80;
uniform vec3 sun_local = vec3(0.0, 1.0, 0.0);   // direction VERS l'étoile (repère monde surface)

varying vec3 v_world_normal;
varying vec3 v_cdir;   // direction MONDE de la lune (occlusion par les nuages)

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_cdir = normalize(MODEL_MATRIX[3].xyz - CAMERA_POSITION_WORLD);
}

void fragment() {
	float l = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 base = mix(COLOR.rgb, vec3(l), desat) * rock_tint * 1.5;
	float lambert = clamp(dot(normalize(v_world_normal), normalize(sun_local)), 0.0, 1.0);
	ALBEDO = base * (0.06 + 0.94 * lambert);   // 0.06 = faible lueur cendrée côté nuit
	ALPHA = cloud_transmittance(v_cdir);        // un nuage devant la lune la voile (le ciel transparaît)
}
