class_name FloatingOrigin
extends RefCounted
## Maths d'aplatissement pour la marche planétaire SANS gravité sphérique.
##
## L'espace-planète contient les positions 3D des chunks SUR la sphère. La transform
## "aplatissante" ramène le point-planète sous le joueur à l'origine monde et aligne
## la normale sphère sur +Y => repère localement plat (gravité droite -Y). Le rebase
## (au seuil) recalcule cette transform autour de la nouvelle position-planète : les
## chunks (espace-planète) sont INCHANGÉS, seule la transform racine bouge => pas de
## distorsion (vraies positions sphériques) et pas de tremblement (joueur ~ origine).

# Repère tangent orthonormé (colonnes = east, up, north) à une direction de sphère.
static func tangent_basis(dir: Vector3) -> Basis:
	var up := dir.normalized()
	var ref := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var east := ref.cross(up).normalized()
	var north := up.cross(east).normalized()
	return Basis(east, up, north)

# Transform aplatissante : monde = M * planète, telle que (planet_dir*radius) -> 0
# et la normale planet_dir -> +Y. heading donné par le repère tangent à planet_dir.
static func flatten(planet_dir: Vector3, radius: float) -> Transform3D:
	var rot := tangent_basis(planet_dir).inverse()   # planète -> monde (east->X, up->Y, north->Z)
	var anchor_world := planet_dir * radius
	return Transform3D(rot, -(rot * anchor_world))
