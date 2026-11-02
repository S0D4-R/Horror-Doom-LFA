class_name RadarHUD
extends Control
# Radar circular: el jugador está al centro, mirando hacia arriba, y el punto rojo es el enemigo.

var jugador: Jugador
var objetivo: Node3D
var alcance: float = 30.0   # metros que cubre el radio del radar
var mapa: Mapa3D   # solo en modo DIJKSTRA: permite dibujar las rutas y la salida

const VERDE := Color(0.2, 1.0, 0.3)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var centro: Vector2 = size / 2.0
	var radio: float = minf(size.x, size.y) / 2.0 - 4.0
	draw_circle(centro, radio, Color(0.0, 0.08, 0.02, 0.75))
	draw_arc(centro, radio, 0.0, TAU, 48, VERDE, 2.0)
	draw_arc(centro, radio * 0.5, 0.0, TAU, 32, Color(VERDE, 0.4), 1.0)
	draw_line(centro, centro + Vector2(0.0, -radio), Color(VERDE, 0.5), 1.0)
	var t: float = Time.get_ticks_msec() / 1000.0
	draw_line(centro, centro + Vector2(cos(t * 2.0), sin(t * 2.0)) * radio, Color(VERDE, 0.35), 2.0)
	draw_circle(centro, 3.0, Color.WHITE)
	if jugador == null or objetivo == null:
		return
	if mapa != null and mapa.es_dijkstra():
		_dibujar_rutas(centro, radio)
	# Posición del enemigo en los ejes del jugador: x = derecha, z = atrás (pantalla: abajo).
	var rel: Vector3 = objetivo.global_position - jugador.global_position
	var local: Vector3 = jugador.global_transform.basis.inverse() * rel
	var p: Vector2 = Vector2(local.x, local.z) / alcance * radio
	if p.length() > radio:
		p = p.normalized() * radio
	draw_circle(centro + p, 5.0, Color(1.0, 0.15, 0.1))


# ---------- Modo DIJKSTRA: rutas sobre el radar ----------

const COLOR_RUTA_JUGADOR := Color(0.3, 0.95, 1.0, 0.95)   # camino más corto a la salida
const COLOR_RUTA_ENEMIGO := Color(1.0, 0.2, 0.1, 0.8)     # camino del enemigo hacia el jugador
const COLOR_SALIDA := Color(0.25, 0.45, 1.0)


func _dibujar_rutas(centro: Vector2, radio: float) -> void:
	# Ruta del enemigo (rojo): empieza en el enemigo y termina en el jugador.
	var enemigo := objetivo as Perseguidor
	if enemigo != null and enemigo.ruta.size() >= 2:
		var pts: Array[Vector3] = [enemigo.global_position]
		for i in range(1, enemigo.ruta.size() - 1):
			pts.append(mapa.celda_a_mundo(enemigo.ruta[i]))
		pts.append(jugador.global_position)
		_trazar(pts, centro, radio, COLOR_RUTA_ENEMIGO)
	# Ruta del jugador a la salida (cian): la posición 0 es su propia celda.
	if mapa.ruta_jugador.size() >= 2:
		var pts: Array[Vector3] = [jugador.global_position]
		for i in range(1, mapa.ruta_jugador.size()):
			pts.append(mapa.celda_a_mundo(mapa.ruta_jugador[i]))
		_trazar(pts, centro, radio, COLOR_RUTA_JUGADOR)
	# Salida (cuadrado azul); si queda fuera del alcance se pega al borde del radar.
	var ps: Vector2 = _a_radar(mapa.celda_a_mundo(mapa.salida), radio)
	if ps.length() > radio:
		ps = ps.normalized() * radio
	draw_rect(Rect2(centro + ps - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), COLOR_SALIDA)


# Posición de un punto del mundo en el radar (relativa al centro, sin recortar al círculo).
func _a_radar(pos_mundo: Vector3, radio: float) -> Vector2:
	var local: Vector3 = jugador.global_transform.basis.inverse() * (pos_mundo - jugador.global_position)
	return Vector2(local.x, local.z) / alcance * radio


func _trazar(puntos: Array[Vector3], centro: Vector2, radio: float, color: Color) -> void:
	var anterior: Vector2 = _a_radar(puntos[0], radio)
	for i in range(1, puntos.size()):
		var actual: Vector2 = _a_radar(puntos[i], radio)
		_segmento_en_circulo(centro, anterior, actual, radio, color)
		anterior = actual


# Dibuja solo la parte del segmento a-b (relativo al centro) que cae dentro del círculo del radar.
func _segmento_en_circulo(centro: Vector2, a: Vector2, b: Vector2, radio: float, color: Color) -> void:
	var d: Vector2 = b - a
	var qa: float = d.dot(d)
	if qa < 0.0001:
		return
	var qb: float = 2.0 * a.dot(d)
	var qc: float = a.dot(a) - radio * radio
	var disc: float = qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return   # el segmento queda por completo fuera del radar
	var raiz: float = sqrt(disc)
	var t0: float = maxf(0.0, (-qb - raiz) / (2.0 * qa))
	var t1: float = minf(1.0, (-qb + raiz) / (2.0 * qa))
	if t0 >= t1:
		return
	draw_line(centro + a + d * t0, centro + a + d * t1, color, 2.0, true)
