class_name HydraulicErosion
extends RefCounted
## Phase 23 — érosion hydraulique SIMPLIFIÉE sur une grille équirectangulaire (lon × lat).
## Approche : PRIORITY-FLOOD (Barnes 2014) qui, en UNE passe déterministe, donne :
##  - une surface « remplie » (filled >= elev) => comble les dépressions, niveau de lac = exutoire ;
##  - un arbre de drainage (parent) sans cul-de-sac => flow accumulation correcte vers les mers ;
##  - les masques rivière (flow > seuil) et lac (filled > terrain au-dessus de la mer) ;
##  - un modificateur d'érosion (creusement des vallées ∝ log du flow, ridges préservés).
## 100 % déterministe (mêmes inputs = même carte). Aucune simulation runtime. Off-thread en prod.
##
## Repère grille : idx = row * w + col. row 0 = pôle Nord, row h-1 = pôle Sud (équirectangulaire).
## Connexité 8-voisins : longitude qui s'enroule (col), pôles bloquants (pas de voisin au-delà).

# Tas binaire min (clé = altitude remplie, départage par compteur d'insertion => ordre déterministe).
class _MinHeap:
	var _k := PackedFloat32Array()   # clés (altitude)
	var _c := PackedInt32Array()     # compteur d'insertion (tie-break)
	var _v := PackedInt32Array()     # valeur (index de cellule)
	var _n := 0

	func reserve(cap: int) -> void:
		_k.resize(cap); _c.resize(cap); _v.resize(cap)

	func size() -> int:
		return _n

	func push(key: float, cnt: int, val: int) -> void:
		var i := _n
		_k[i] = key; _c[i] = cnt; _v[i] = val
		_n += 1
		while i > 0:
			var p := (i - 1) >> 1
			if _less(i, p):
				_swap(i, p); i = p
			else:
				break

	func pop_val() -> int:
		var top := _v[0]
		_n -= 1
		if _n > 0:
			_k[0] = _k[_n]; _c[0] = _c[_n]; _v[0] = _v[_n]
			var i := 0
			while true:
				var l := i * 2 + 1
				var r := l + 1
				var m := i
				if l < _n and _less(l, m): m = l
				if r < _n and _less(r, m): m = r
				if m == i: break
				_swap(i, m); i = m
		return top

	func _less(a: int, b: int) -> bool:
		if _k[a] != _k[b]:
			return _k[a] < _k[b]
		return _c[a] < _c[b]

	func _swap(a: int, b: int) -> void:
		var tk := _k[a]; _k[a] = _k[b]; _k[b] = tk
		var tc := _c[a]; _c[a] = _c[b]; _c[b] = tc
		var tv := _v[a]; _v[a] = _v[b]; _v[b] = tv

# Calcule la carte hydrologique à partir du champ d'altitude `elev` (taille w*h).
# Renvoie un Dictionary de PackedArrays (voir clés en fin de fonction).
static func compute(elev: PackedFloat32Array, w: int, h: int, sea_level: float, params: Dictionary) -> Dictionary:
	var n := w * h
	# Décalages 8-voisins (col, row) + index de direction k (0..7).
	var off_dc := PackedInt32Array([-1, 0, 1, -1, 1, -1, 0, 1])
	var off_dr := PackedInt32Array([-1, -1, -1, 0, 0, 1, 1, 1])
	var filled := elev.duplicate()
	var parent := PackedInt32Array(); parent.resize(n); parent.fill(-1)
	var dir8 := PackedByteArray(); dir8.resize(n); dir8.fill(255)
	var visited := PackedByteArray(); visited.resize(n)
	var order := PackedInt32Array(); order.resize(n)   # ordre de pop (altitude croissante)
	var order_n := 0

	# Poids de cellule ∝ aire (cos latitude) : évite des rivières polaires fantômes.
	var row_w := PackedFloat32Array(); row_w.resize(h)
	for row in h:
		var lat: float = PI * 0.5 - (float(row) + 0.5) / float(h) * PI
		row_w[row] = maxf(cos(lat), 0.02)

	var heap := _MinHeap.new()
	heap.reserve(n)
	var ctr := 0

	# Graines (exutoires) : toutes les cellules océan (elev <= mer). Repli : la cellule la plus basse.
	var has_ocean := false
	for i in n:
		if elev[i] <= sea_level:
			has_ocean = true
			break
	if has_ocean:
		for i in n:
			if elev[i] <= sea_level:
				filled[i] = sea_level
				visited[i] = 1
				heap.push(sea_level, ctr, i); ctr += 1
	else:
		var lo_i := 0
		var lo_v := elev[0]
		for i in n:
			if elev[i] < lo_v:
				lo_v = elev[i]; lo_i = i
		visited[lo_i] = 1
		heap.push(elev[lo_i], ctr, lo_i); ctr += 1

	# Priority-flood : on inonde depuis les exutoires vers le haut.
	while heap.size() > 0:
		var c := heap.pop_val()
		order[order_n] = c; order_n += 1
		var crow: int = c / w
		var ccol: int = c % w
		for k in 8:
			var nr := crow + off_dr[k]
			if nr < 0 or nr >= h:
				continue                      # pôle : pas de voisin au-delà
			var nc := ccol + off_dc[k]
			if nc < 0: nc += w                # enroulement longitude
			elif nc >= w: nc -= w
			var ni := nr * w + nc
			if visited[ni] != 0:
				continue
			visited[ni] = 1
			var fv: float = maxf(elev[ni], filled[c])
			filled[ni] = fv
			parent[ni] = c
			dir8[ni] = k                      # direction de ni VERS c (aval)
			heap.push(fv, ctr, ni); ctr += 1

	# Flow accumulation : on remonte l'arbre de drainage (ordre inverse du pop = de l'amont vers l'aval).
	var flow := PackedFloat32Array(); flow.resize(n)
	for i in n:
		var row: int = i / w
		flow[i] = row_w[row]                  # « pluie » pondérée par l'aire de cellule
	for oi in range(order_n - 1, -1, -1):
		var c := order[oi]
		var p := parent[c]
		if p >= 0:
			flow[p] += flow[c]

	# Flow max sur terre (normalisation viz + seuils).
	var max_flow := 1.0
	for i in n:
		if elev[i] > sea_level and flow[i] > max_flow:
			max_flow = flow[i]

	# Érosion (creusement vallées) + masques rivière/lac.
	var sev: float = params.get("erosion_severity", 0.045)
	var river_thr: float = params.get("river_threshold", 55.0)
	var lake_depth: float = params.get("lake_min_depth", 0.012)   # remplissage mini pour qu'une cuvette compte comme lac (~2 m à l'échelle surface)
	var erosion := PackedFloat32Array(); erosion.resize(n)
	var river := PackedFloat32Array(); river.resize(n)
	var is_lake := PackedByteArray(); is_lake.resize(n)
	var lake_lvl := PackedFloat32Array(); lake_lvl.resize(n)
	var log_lo := log(2.0)
	var log_hi := log(max_flow * 0.25 + 2.0)
	var inv_log := 1.0 / maxf(log_hi - log_lo, 0.001)
	for i in n:
		if elev[i] <= sea_level:
			continue                          # océan : ni érosion ni rivière ni lac
		# Creusement ∝ log(flow) borné : vallées douces, crêtes (flow faible) préservées.
		var nrm := clampf((log(flow[i] + 1.0) - log_lo) * inv_log, 0.0, 1.0)
		erosion[i] = -sev * nrm
		# Rivière : au-dessus d'un seuil de drainage ; force 0..1 = proxy de largeur.
		if flow[i] > river_thr:
			river[i] = clampf((flow[i] - river_thr) / (river_thr * 7.0), 0.0, 1.0)
		# Lac : surface de remplissage au-dessus du terrain ET au-dessus de la mer (bassin sans exutoire bas).
		if filled[i] > elev[i] + lake_depth and filled[i] > sea_level + 0.001:
			is_lake[i] = 1
			lake_lvl[i] = filled[i]

	# Taille de bassin minimale : élimine les micro-lacs (pits d'1 à quelques cellules dus au bruit).
	# Étiquetage des composantes connexes (4-voisins, longitude enroulée, pôles bloquants).
	var min_cells: int = params.get("lake_min_cells", 6)
	if min_cells > 1:
		var dc4 := PackedInt32Array([0, 0, -1, 1])
		var dr4 := PackedInt32Array([-1, 1, 0, 0])
		var seen := PackedByteArray(); seen.resize(n)
		var stack := PackedInt32Array()
		for start in n:
			if is_lake[start] == 0 or seen[start] != 0:
				continue
			stack.clear()
			stack.push_back(start)
			seen[start] = 1
			var comp := PackedInt32Array()
			while not stack.is_empty():
				var c: int = stack[stack.size() - 1]
				stack.remove_at(stack.size() - 1)
				comp.push_back(c)
				var cr: int = c / w
				var cc: int = c % w
				for k in 4:
					var nr := cr + dr4[k]
					if nr < 0 or nr >= h:
						continue
					var nc := cc + dc4[k]
					if nc < 0: nc += w
					elif nc >= w: nc -= w
					var ni := nr * w + nc
					if is_lake[ni] != 0 and seen[ni] == 0:
						seen[ni] = 1
						stack.push_back(ni)
			if comp.size() < min_cells:
				for ci in comp:
					is_lake[ci] = 0
					lake_lvl[ci] = 0.0

	return {
		"filled": filled,
		"flow": flow,
		"dir8": dir8,
		"erosion": erosion,
		"river": river,
		"is_lake": is_lake,
		"lake_level": lake_lvl,
		"max_flow": max_flow,
	}
