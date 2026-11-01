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
