class_name Grafo
extends RefCounted
# Convención: una celda es Vector2i(x = columna, y = fila), y se accede como matriz[y][x].
# 0 = piso, 1 = muro.
 
# Carga un mapa .txt. Las líneas que empiezan con '#' son cabecera; el resto son filas de 0 y 1.
static func cargar(ruta: String) -> Dictionary:
	var datos := {
		"matriz": [],
		"jugador": Vector2i.ZERO,
		"salida": Vector2i.ZERO,
		"enemigo": Vector2i.ZERO,
	}
	var f := FileAccess.open(ruta, FileAccess.READ)
	if f == null:
		push_error("No se pudo abrir el mapa: " + ruta)
		return datos
	while not f.eof_reached():
		var linea := f.get_line().strip_edges()
		if linea == "":
			continue
		if linea.begins_with("#"):
			_leer_cabecera(linea, datos)
			continue
		var fila: Array = []
		for ch in linea:
			fila.append(int(ch))
		datos["matriz"].append(fila)
	return datos
 
 
# Lee tokens como "jugador=22,56" (fila,columna) y los guarda como Vector2i(columna, fila).
static func _leer_cabecera(linea: String, datos: Dictionary) -> void:
	for token in linea.split(" "):
		if not token.contains("="):
			continue
		var kv := token.split("=")
		if kv[0] in ["jugador", "salida", "enemigo"]:
			var p := kv[1].split(",")
			datos[kv[0]] = Vector2i(int(p[1]), int(p[0]))
 
 
static func es_piso(m: Array, c: Vector2i) -> bool:
	return c.y >= 0 and c.y < m.size() and c.x >= 0 and c.x < m[c.y].size() and m[c.y][c.x] == 0
 
 
# Vecinos en 4 direcciones (las aristas del grafo). Lo usará Dijkstra.
static func vecinos(m: Array, c: Vector2i) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if es_piso(m, c + d):
			res.append(c + d)
	return res
 
 
# ---------- Dijkstra ----------
# Camino más corto entre dos celdas de piso. Cada arista (celda -> vecino) cuesta 1.
# Devuelve la ruta incluyendo inicio y meta; si no hay camino, devuelve un arreglo vacío.
static func dijkstra(m: Array, inicio: Vector2i, meta: Vector2i) -> Array[Vector2i]:
	var ruta: Array[Vector2i] = []
	if not es_piso(m, inicio) or not es_piso(m, meta):
		return ruta
	var dist: Dictionary = {inicio: 0}
	var previo: Dictionary = {}
	var cola: Array = [[0, inicio]]   # min-heap de [distancia, celda]
	while not cola.is_empty():
		var actual: Array = _heap_sacar(cola)
		var d: int = actual[0]
		var u: Vector2i = actual[1]
		if d > dist.get(u, 1 << 30):
			continue   # entrada vieja de la cola
		if u == meta:
			break
		for v in vecinos(m, u):
			var nd: int = d + 1
			if nd < dist.get(v, 1 << 30):
				dist[v] = nd
				previo[v] = u
				_heap_meter(cola, [nd, v])
	if not dist.has(meta):
		return ruta
	var c: Vector2i = meta
	ruta.append(c)
	while c != inicio:
		c = previo[c]
		ruta.append(c)
	ruta.reverse()
	return ruta
 
 
static func _heap_meter(h: Array, item: Array) -> void:
	h.append(item)
	var i: int = h.size() - 1
	while i > 0:
		var padre: int = (i - 1) / 2
		if h[padre][0] <= h[i][0]:
			break
		var tmp: Array = h[padre]
		h[padre] = h[i]
		h[i] = tmp
		i = padre
 
 
static func _heap_sacar(h: Array) -> Array:
	var raiz: Array = h[0]
	var ultimo: Array = h.pop_back()
	if not h.is_empty():
		h[0] = ultimo
		var i: int = 0
		while true:
			var izq: int = 2 * i + 1
			var der: int = izq + 1
			var menor: int = i
			if izq < h.size() and h[izq][0] < h[menor][0]:
				menor = izq
			if der < h.size() and h[der][0] < h[menor][0]:
				menor = der
			if menor == i:
				break
			var tmp: Array = h[menor]
			h[menor] = h[i]
			h[i] = tmp
			i = menor
	return raiz
 
