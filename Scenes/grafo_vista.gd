class_name GrafoVista
extends Control
# Vista del grafo del laberinto (tecla Z, solo en el modo DIJKSTRA).
# Cada celda de piso es un nodo y cada par de celdas vecinas es una arista (costo 1).
# Muestra además la ruta más corta del jugador a la salida (cian) y la del enemigo hacia el jugador (rojo).
# El juego NO se pausa mientras está abierta: el enemigo sigue avanzando por su ruta.
 
const COLOR_FONDO := Color(0.0, 0.02, 0.05, 0.9)
const COLOR_ARISTA := Color(0.25, 0.45, 0.75, 0.55)
const COLOR_NODO := Color(0.55, 0.75, 1.0, 0.9)
const COLOR_RUTA_JUGADOR := Color(0.3, 0.95, 1.0)
const COLOR_RUTA_ENEMIGO := Color(1.0, 0.2, 0.1)
const COLOR_SALIDA := Color(0.25, 0.45, 1.0)
const COLOR_JUGADOR := Color(0.2, 1.0, 0.3)
const COLOR_TEXTO := Color(0.85, 0.9, 1.0)
 
# Sin tipo declarado a propósito: Mapa3D -> HUD -> GrafoVista -> Mapa3D sería una dependencia
# circular entre scripts y Godot no logra resolver sus miembros ("Could not resolve external class member").
var mapa            # Mapa3D
var jugador         # Jugador
var enemigo         # EnemigoPerseguidor
 
var _nodos: PackedVector2Array = PackedVector2Array()     # centros de celda, en unidades de celda
var _aristas: PackedVector2Array = PackedVector2Array()   # pares de puntos (inicio, fin)
var _origen: Vector2 = Vector2.ZERO
var _esc: float = 1.0   # píxeles por celda
 
 
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
 
 
# Arma la lista de nodos y aristas una sola vez (el laberinto no cambia durante la partida).
func preparar(m, j, e) -> void:
	mapa = m
	jugador = j
	enemigo = e
	_nodos.clear()
	_aristas.clear()
	for y in m.matriz.size():
		for x in m.matriz[y].size():
			var c := Vector2i(x, y)
			if not Grafo.es_piso(m.matriz, c):
				continue
			var centro := Vector2(x + 0.5, y + 0.5)
			_nodos.append(centro)
			# Solo derecha y abajo, para no repetir cada arista dos veces.
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				if Grafo.es_piso(m.matriz, c + d):
					_aristas.append(centro)
					_aristas.append(Vector2(c.x + d.x + 0.5, c.y + d.y + 0.5))
 
 
func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
 
 
func _p(celda: Vector2) -> Vector2:
	return _origen + celda * _esc
 
 
# Posición del mundo 3D expresada en unidades de celda (continua, no entera).
func _celda_de(pos: Vector3) -> Vector2:
	return Vector2(pos.x, pos.z) / mapa.tam_celda
 
 
func _centro_celda(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)
 
 
func _draw() -> void:
	if mapa == null or jugador == null or mapa.matriz.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_FONDO)
 
	# Escala para que todo el laberinto quepa en pantalla.
	var filas: int = mapa.matriz.size()
	var cols: int = mapa.matriz[0].size()
	var area := Vector2(size.x - 48.0, size.y - 100.0)
	_esc = maxf(2.0, minf(area.x / cols, area.y / filas))
	_origen = Vector2((size.x - cols * _esc) / 2.0, 56.0 + (area.y - filas * _esc) / 2.0)
 
	# Aristas (todas de una vez) y nodos.
	var seg := PackedVector2Array()
	seg.resize(_aristas.size())
	for i in _aristas.size():
		seg[i] = _p(_aristas[i])
	draw_multiline(seg, COLOR_ARISTA, maxf(1.0, _esc * 0.12))
	var r: float = maxf(1.2, _esc * 0.16)
	for n in _nodos:
		var q: Vector2 = _p(n)
		draw_rect(Rect2(q - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), COLOR_NODO)
 
	var grosor: float = maxf(2.0, _esc * 0.3)
	var pos_jugador: Vector2 = _celda_de(jugador.global_position)
 
	# Ruta del enemigo hacia el jugador (la calcula el propio enemigo con Dijkstra).
	var pasos_enemigo: int = 0
	if enemigo != null:
		pasos_enemigo = maxi(0, enemigo.ruta.size() - 1)
		if enemigo.ruta.size() >= 2:
			var pe := PackedVector2Array()
			pe.append(_p(_celda_de(enemigo.global_position)))
			for i in range(1, enemigo.ruta.size() - 1):
				pe.append(_p(_centro_celda(enemigo.ruta[i])))
			pe.append(_p(pos_jugador))
			draw_polyline(pe, COLOR_RUTA_ENEMIGO, grosor, true)
 
	# Ruta más corta del jugador a la salida.
	var pasos_salida: int = maxi(0, mapa.ruta_jugador.size() - 1)
	if mapa.ruta_jugador.size() >= 2:
		var pj := PackedVector2Array()
		pj.append(_p(pos_jugador))
		for i in range(1, mapa.ruta_jugador.size()):
			pj.append(_p(_centro_celda(mapa.ruta_jugador[i])))
		draw_polyline(pj, COLOR_RUTA_JUGADOR, grosor, true)
 
	# Salida, enemigo y jugador (con una punta que indica hacia dónde mira).
	var ps: Vector2 = _p(_centro_celda(mapa.salida))
	var lado: float = maxf(4.0, _esc * 0.7)
	draw_rect(Rect2(ps - Vector2(lado, lado), Vector2(lado * 2.0, lado * 2.0)), COLOR_SALIDA)
	if enemigo != null:
		draw_circle(_p(_celda_de(enemigo.global_position)), lado, COLOR_RUTA_ENEMIGO)
	var pj_px: Vector2 = _p(pos_jugador)
	var dir3: Vector3 = -jugador.global_transform.basis.z
	var dir := Vector2(dir3.x, dir3.z).normalized()
	var perp := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		pj_px + dir * lado * 1.6,
		pj_px - dir * lado + perp * lado,
		pj_px - dir * lado - perp * lado,
	]), COLOR_JUGADOR)
 
	# Textos: título arriba, leyenda y datos abajo.
	var fuente: Font = ThemeDB.fallback_font
	draw_string(fuente, Vector2(24.0, 34.0), "GRAFO DEL LABERINTO  ·  Z: cerrar",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, COLOR_TEXTO)
	draw_string(fuente, Vector2(24.0, size.y - 36.0),
		"Nodos: %d   Aristas: %d   Pasos a la salida: %d   Pasos del enemigo hacia ti: %d" % [
			_nodos.size(), _aristas.size() / 2, pasos_salida, pasos_enemigo],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, COLOR_TEXTO)
	_leyenda(fuente, Vector2(24.0, size.y - 12.0))
 
 
func _leyenda(fuente: Font, desde: Vector2) -> void:
	var x: float = desde.x
	for item in [
		[COLOR_JUGADOR, "Tú"],
		[COLOR_SALIDA, "Salida"],
		[COLOR_RUTA_JUGADOR, "Tu ruta más corta"],
		[COLOR_RUTA_ENEMIGO, "Enemigo / su ruta hacia ti"],
	]:
		draw_rect(Rect2(x, desde.y - 11.0, 12.0, 12.0), item[0])
		draw_string(fuente, Vector2(x + 18.0, desde.y), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, COLOR_TEXTO)
		x += 40.0 + item[1].length() * 8.0
 