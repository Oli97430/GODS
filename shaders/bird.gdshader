shader_type spatial;
render_mode cull_disabled, unshaded, shadows_disabled, fog_disabled;
// Oiseau d'une nuée : chevron sombre (silhouette contre le ciel) avec BATTEMENT D'AILES — les bouts d'aile
// (|VERTEX.x| grand) montent/descendent, le corps (x~0) reste. Phase par instance => le troupeau n'est pas
// synchrone. INSTANCE_CUSTOM.x = phase de battement. Opaque + non éclairé (très cheap, lisible à distance).

uniform vec3 body : source_color = vec3(0.06, 0.07, 0.09);   // silhouette sombre
uniform float flap_speed = 7.0;

void vertex() {
	float flap = sin(TIME * flap_speed + INSTANCE_CUSTOM.x * 6.2831);
	VERTEX.y += abs(VERTEX.x) * flap * 0.45;   // bouts d'aile : battement
}

void fragment() {
	ALBEDO = body;
}
