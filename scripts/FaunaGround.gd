class_name FaunaGround
extends RefCounted
## Échantillonneur de hauteur de sol LOCAL à un chunk (phase 19) — sans raycast (brief).
## Convertit une position LOCALE (x,z) du repère du chunk en hauteur de sol locale, en utilisant
## EXACTEMENT la même formule que le mesh du terrain (PlanetGenerator.sample_elevation) :
##   local (x,0,z) -> point planète -> direction -> élévation -> point sphère -> retour en local.
## Le repère (center, tangent basis) du chunk est en espace PLANET-ROOT (invariant au rebase, car
## les chunks sont relatifs à PlanetRoot). pg est une instance MAIN-THREAD partagée (sampling pur).

var _pg: PlanetGenerator
var _center: Vector3        # centre du chunk en espace planète (dir_c * phys_radius)
var _tb: Basis              # base tangente au centre (= transform.basis du chunk)
var _inv: Basis             # tangente inverse (planète -> local)
var _phys_radius: float
var _vertical_scale: float
var _sea: float

func _init(pg: PlanetGenerator, center: Vector3, tb: Basis, phys_radius: float, vertical_scale: float, sea: float) -> void:
	_pg = pg
	_center = center
	_tb = tb
	_inv = tb.inverse()
	_phys_radius = phys_radius
	_vertical_scale = vertical_scale
	_sea = sea

# Hauteur de sol LOCALE (y du repère du chunk) sous la position locale horizontale (lx, lz).
func local_ground_y(lx: float, lz: float) -> float:
	var p0 := _center + _tb * Vector3(lx, 0.0, lz)
	var dir := p0.normalized()
	var e: float = maxf(_pg.sample_elevation(dir), _sea)
	var sphere := dir * (_phys_radius + e * _vertical_scale)
	return (_inv * (sphere - _center)).y

# Direction-planète (unitaire) du centre du chunk — pour l'altitude solaire locale (jour/nuit).
func planet_dir() -> Vector3:
	return _center.normalized()
