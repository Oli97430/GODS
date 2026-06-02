class_name Paraglider
extends Node3D
## Voilure de parapente PROCÉDURALE (code-only) : voile arquée à caissons alternés + suspentes,
## affichée au-dessus du joueur pendant le vol plané. S'incline (roll) dans les virages et tangue
## (pitch) selon la vitesse. Pivot = point d'attache (épaules) ; positionnée par PlayerController.

const SPAN := 7.0          # envergure (m)
const CHORD := 2.6         # corde (m)
const ARCH := 1.7          # flèche de l'arc (bouts de l'aile plus bas que le centre)
const HEIGHT_ABOVE := 5.5  # hauteur de la voile au-dessus du point d'attache
const NU := 16             # segments d'envergure
const NV := 5              # segments de corde

var _bank := 0.0
var _pitch := 0.0

func _ready() -> void:
	var canopy := MeshInstance3D.new()
	canopy.mesh = _build_canopy()
	canopy.material_override = _canopy_material()
	add_child(canopy)
	var lines := MeshInstance3D.new()
	lines.mesh = _build_lines()
	lines.material_override = _line_material()
	add_child(lines)
	visible = false

# Point de la voile (i: 0..NU envergure, j: 0..NV corde) : arc en envergure + légère cambrure en corde.
func _point(i: int, j: int) -> Vector3:
	var u := float(i) / float(NU) * 2.0 - 1.0   # -1..1
	var v := float(j) / float(NV)               # 0..1
	var x := u * SPAN * 0.5
	var z := (v - 0.5) * CHORD                   # corde le long de z (avant = -z, comme le joueur)
	var y := HEIGHT_ABOVE - ARCH * u * u - 0.18 * sin(v * PI)
	return Vector3(x, y, z)

func _build_canopy() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in NV:
		for i in NU:
			var col := Color(0.95, 0.55, 0.20) if (i % 2 == 0) else Color(0.93, 0.93, 0.91)  # caissons alternés
			var a := _point(i, j)
			var b := _point(i + 1, j)
			var c := _point(i + 1, j + 1)
			var d := _point(i, j + 1)
			for p in [a, b, c, a, c, d]:
				st.set_color(col)
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()

func _build_lines() -> ImmediateMesh:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var attach_l := Vector3(-0.22, 0.0, 0.0)   # épaule gauche
	var attach_r := Vector3(0.22, 0.0, 0.0)    # épaule droite
	for k in 5:
		var u := -0.8 + float(k) * 0.4
		var i := int(round((u + 1.0) * 0.5 * float(NU)))
		var att := attach_l if u < 0.0 else attach_r
		for jj in [0, NV]:   # bord d'attaque + bord de fuite
			im.surface_add_vertex(_point(i, jj))
			im.surface_add_vertex(att)
	im.surface_end()
	return im

func _canopy_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # visible du dessous
	m.roughness = 0.9
	m.emission_enabled = true                    # reste lisible à l'ombre / contre-jour
	m.emission = Color(0.5, 0.35, 0.2)
	m.emission_energy_multiplier = 0.12
	return m

func _line_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.08, 0.08, 0.10)
	return m

func deploy() -> void:
	visible = true

func stow() -> void:
	visible = false

# Attitude visuelle : roule dans le virage (bank) + tangue selon la vitesse (pitch). Lissée.
func set_attitude(bank: float, pitch: float, delta: float) -> void:
	var t := clampf(6.0 * delta, 0.0, 1.0)
	_bank = lerpf(_bank, bank, t)
	_pitch = lerpf(_pitch, pitch, t)
	rotation = Vector3(_pitch, 0.0, -_bank * 0.5)
