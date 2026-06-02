class_name POIInstance
extends RefCounted
## Phase 20 — COUCHE C : DESCRIPTEUR léger d'un POI (lieu d'intérêt) calculé hors-thread par
## POIDistributor (calcul PUR : présence + catégorie + placement + nom). Ne contient AUCUN Node ni
## mesh => transportable via le ready-queue du ChunkManager (comme les semis de végétation/clutter).
## L'instance visuelle (Node3D) est construite plus tard, MAIN-THREAD budgétée, par POILibrary.generate.

var category: int = -1               # POILibrary.Category (-1 = aucun POI dans ce chunk)
var local_transform := Transform3D.IDENTITY   # pose dans le repère LOCAL du chunk (posé au sol + lacet)
var seed_val: int = 0                # graine déterministe du POI (mesh + variations)
var poi_name: String = ""            # nom propre (POI notables) ou "" (mineurs/anonymes)

func is_valid() -> bool:
	return category >= 0

func is_named() -> bool:
	return poi_name != ""
