class_name RadarHUD
extends Control
# Radar / minimapa 2D con Dijkstra a la salida.
#
# Funciones:
#   • Dibuja el laberinto como minimapa en el círculo del radar.
#   • Traza la ruta óptima (Dijkstra) desde el jugador hasta la salida en COLOR_RUTA.
#   • Cada SCANS_POR_HINT scans de línea giratoria muestra la DIRECCIÓN (flecha) al perk más cercano.
#   • El radar dura RADAR_DURACION segundos (definido en jugador.gd, ahora 7 s).
#
# MODO DIJKSTRA (mapa_ref.es_dijkstra()):
#   • El radar está siempre visible (lo decide el HUD).
#   • Ruta CIAN : camino más corto del jugador a la salida (Dijkstra, se actualiza en cada celda).
#   • Ruta ROJA : camino más corto del enemigo hacia el jugador (el Dijkstra del propio enemigo).
#   • Debajo del radar se muestran los pasos que faltan en cada ruta.

var jugador: Jugador
var objetivo: Node3D          # referencia al nodo del enemigo (punto rojo)
var alcance: float = 30.0    # metros que cubre el radio del radar
var mapa_ref: Mapa3D          # asignado desde HUD.conectar o mapa_3d.gd

# Datos del mapa (se rellenan cuando mapa_ref está disponible)
var _matriz: Array = []
var _salida: Vector2i = Vector2i(-1, -1)
var _ruta_salida: Array[Vector2i] = []   # ruta Dijkstra jugador → salida
var _t_recalculo_ruta: float = 0.0
const INTERVALO_RUTA: float = 1.5       # recalcular la ruta cada 1.5 s

# Hint de perk: cada SCANS_POR_HINT vueltas completas del escáner se muestra la dirección al perk
var _scan_angle: float = 0.0
var _scans_completados: int = 0
const SCANS_POR_HINT: int = 3           # cada 3 giros muestra la flecha de perk
const VELOCIDAD_SCAN: float = TAU / 2.5 # un giro completo en 2.5 segundos
var _mostrar_hint_perk: bool = false
var _dir_perk: Vector2 = Vector2.ZERO   # dirección normalizada hacia el perk más cercano
var _t_hint: float = 0.0
const DURACION_HINT: float = 1.8        # segundos que se muestra la flecha

const VERDE := Color(0.2, 1.0, 0.3)
const COLOR_RUTA := Color(0.95, 0.85, 0.15, 0.85)   # amarillo-ámbar para la ruta
const COLOR_SALIDA := Color(0.2, 0.5, 1.0)
const COLOR_PERK_HINT := Color(1.0, 0.65, 0.0)      # naranja para la flecha de perk
const COLOR_RUTA_JUGADOR := Color(0.3, 0.95, 1.0, 0.95)   # modo DIJKSTRA: tu camino a la salida
const COLOR_RUTA_ENEMIGO := Color(1.0, 0.2, 0.1, 0.85)    # modo DIJKSTRA: camino del enemigo hacia ti


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not visible:
		return

	# Avanzar escáner
	var angulo_anterior: float = _scan_angle
	_scan_angle += VELOCIDAD_SCAN * delta
	if _scan_angle >= TAU:
		_scan_angle = fmod(_scan_angle, TAU)
		_scans_completados += 1
		if _scans_completados % SCANS_POR_HINT == 0:
			_activar_hint_perk()

	# Recalcular ruta Dijkstra periódicamente
	if jugador != null and mapa_ref != null and not mapa_ref.matriz.is_empty():
		_t_recalculo_ruta -= delta
		if _t_recalculo_ruta <= 0.0:
			_t_recalculo_ruta = INTERVALO_RUTA
			_recalcular_ruta()

	# Apagar hint tras su duración
	if _mostrar_hint_perk:
		_t_hint -= delta
		if _t_hint <= 0.0:
			_mostrar_hint_perk = false

	queue_redraw()


func _recalcular_ruta() -> void:
	if jugador == null or mapa_ref == null:
		return
	if _salida == Vector2i(-1, -1):
		_salida = mapa_ref.salida
		_matriz = mapa_ref.matriz
	_ruta_salida = Grafo.dijkstra(_matriz, jugador.celda_actual, _salida)


func _activar_hint_perk() -> void:
	# Buscar el perk más cercano al jugador en el mapa
	if jugador == null or mapa_ref == null:
		return
	var mejor_dist: float = INF
	var mejor_dir: Vector2 = Vector2.ZERO
	for tipo in mapa_ref.posiciones_perks:
		var celda_perk: Vector2i = mapa_ref.posiciones_perks[tipo]
		var pos_perk: Vector3 = mapa_ref.celda_a_mundo(celda_perk)
		var dif := Vector2(pos_perk.x - jugador.global_position.x,
						   pos_perk.z - jugador.global_position.z)
		var d := dif.length()
		if d < mejor_dist:
			mejor_dist = d
			mejor_dir = dif.normalized() if d > 0.01 else Vector2.ZERO
	if mejor_dir != Vector2.ZERO:
		# Rotar la dirección al espacio local del jugador (igual que el punto del enemigo)
		var angulo_jugador: float = jugador.rotation.y
		mejor_dir = mejor_dir.rotated(-angulo_jugador)
		_dir_perk = mejor_dir
		_mostrar_hint_perk = true
		_t_hint = DURACION_HINT


func _draw() -> void:
	var centro: Vector2 = size / 2.0
	var radio: float = minf(size.x, size.y) / 2.0 - 4.0

	# Fondo y círculos de referencia
	draw_circle(centro, radio, Color(0.0, 0.08, 0.02, 0.75))
	draw_arc(centro, radio, 0.0, TAU, 48, VERDE, 2.0)
	draw_arc(centro, radio * 0.5, 0.0, TAU, 32, Color(VERDE, 0.4), 1.0)
	draw_line(centro, centro + Vector2(0.0, -radio), Color(VERDE, 0.5), 1.0)

	# Escáner giratorio
	draw_line(centro,
		centro + Vector2(cos(_scan_angle - PI * 0.5), sin(_scan_angle - PI * 0.5)) * radio,
		Color(VERDE, 0.35), 2.0)

	# ── Minimapa: dibujar celdas del laberinto visibles en el radio ──────
	_dibujar_mapa(centro, radio)

	# ── Ruta a la salida ─────────────────────────────────────────────────
	_dibujar_ruta(centro, radio)

	# ── Modo DIJKSTRA: ruta del enemigo hacia el jugador ─────────────────
	_dibujar_ruta_enemigo(centro, radio)

	# ── Jugador (centro) ─────────────────────────────────────────────────
	draw_circle(centro, 3.5, Color.WHITE)
	# Triángulo indicando la dirección que mira el jugador (hacia arriba del radar)
	var punta: Vector2 = centro + Vector2(0, -6.0)
	var base_l: Vector2 = centro + Vector2(-3.5, 2.0)
	var base_r: Vector2 = centro + Vector2(3.5, 2.0)
	draw_colored_polygon(PackedVector2Array([punta, base_l, base_r]), Color(1.0, 1.0, 0.5, 0.9))

	# ── Enemigo ───────────────────────────────────────────────────────────
	if jugador != null and objetivo != null and is_instance_valid(objetivo):
		var rel: Vector3 = objetivo.global_position - jugador.global_position
		var local: Vector3 = jugador.global_transform.basis.inverse() * rel
		var p: Vector2 = Vector2(local.x, local.z) / alcance * radio
		if p.length() > radio:
			p = p.normalized() * (radio - 3.0)
		draw_circle(centro + p, 5.5, Color(1.0, 0.15, 0.1))

	# ── Salida ────────────────────────────────────────────────────────────
	if jugador != null and mapa_ref != null and _salida != Vector2i(-1, -1):
		var pos_salida: Vector3 = mapa_ref.celda_a_mundo(_salida)
		var rel_s: Vector3 = pos_salida - jugador.global_position
		var local_s: Vector3 = jugador.global_transform.basis.inverse() * rel_s
		var ps: Vector2 = Vector2(local_s.x, local_s.z) / alcance * radio
		if ps.length() > radio:
			ps = ps.normalized() * (radio - 4.0)
		draw_circle(centro + ps, 5.0, Color(0.0, 0.0, 0.0, 0.7))
		draw_circle(centro + ps, 4.0, COLOR_SALIDA)

	# ── Hint de perk (flecha) ─────────────────────────────────────────────
	if _mostrar_hint_perk and _dir_perk != Vector2.ZERO:
		var alpha: float = clampf(_t_hint / DURACION_HINT, 0.0, 1.0)
		var col_hint := Color(COLOR_PERK_HINT.r, COLOR_PERK_HINT.g, COLOR_PERK_HINT.b, alpha)
		var flecha_fin: Vector2 = centro + _dir_perk * radio * 0.72
		draw_line(centro, flecha_fin, col_hint, 3.0)
		# Cabeza de la flecha
		var perp: Vector2 = Vector2(-_dir_perk.y, _dir_perk.x)
		var p1: Vector2 = flecha_fin - _dir_perk * 10.0 + perp * 6.0
		var p2: Vector2 = flecha_fin - _dir_perk * 10.0 - perp * 6.0
		draw_colored_polygon(PackedVector2Array([flecha_fin, p1, p2]),
			Color(col_hint.r, col_hint.g, col_hint.b, alpha * 0.9))

	# ── Modo DIJKSTRA: pasos restantes de cada ruta ───────────────────────
	_dibujar_info_dijkstra()


func _dibujar_mapa(centro: Vector2, radio: float) -> void:
	if jugador == null or _matriz.is_empty():
		return
	var tam: float = mapa_ref.tam_celda if mapa_ref != null else 2.0
	var px_celda: float = radio / (alcance / tam) * 1.0   # píxeles por celda en el radar
	var min_px: float = 1.5   # no dibujar celdas menores a esto

	for y in _matriz.size():
		for x in _matriz[y].size():
			if _matriz[y][x] != 1:
				continue
			# Posición mundo de esta celda de muro
			var mundo_x: float = (x + 0.5) * tam
			var mundo_z: float = (y + 0.5) * tam
			var rel: Vector3 = Vector3(mundo_x, 0.0, mundo_z) - jugador.global_position
			var local: Vector3 = jugador.global_transform.basis.inverse() * rel
			var p: Vector2 = Vector2(local.x, local.z) / alcance * radio
			# Solo dibujar si está dentro del círculo
			if p.length() > radio - px_celda:
				continue
			var rect_pos: Vector2 = centro + p - Vector2(px_celda, px_celda) * 0.5
			draw_rect(Rect2(rect_pos, Vector2(max(px_celda, min_px), max(px_celda, min_px))),
				Color(0.5, 0.5, 0.55, 0.6))


func _es_dijkstra() -> bool:
	return mapa_ref != null and mapa_ref.es_dijkstra()


func _dibujar_ruta(centro: Vector2, radio: float) -> void:
	if jugador == null or mapa_ref == null:
		return
	if _es_dijkstra():
		# Ruta viva (se recalcula cada vez que el jugador cambia de celda). La posición 0 es su
		# propia celda, así que el trazo parte de donde está parado realmente.
		var ruta: Array[Vector2i] = mapa_ref.ruta_jugador
		if ruta.size() < 2:
			return
		var pts: Array[Vector3] = [jugador.global_position]
		for i in range(1, ruta.size()):
			pts.append(mapa_ref.celda_a_mundo(ruta[i]))
		_trazar(pts, centro, radio, COLOR_RUTA_JUGADOR, 2.5)
		return
	if _ruta_salida.size() < 2:
		return
	var tam: float = mapa_ref.tam_celda
	var puntos: PackedVector2Array = []
	for celda in _ruta_salida:
		var mundo_x: float = (celda.x + 0.5) * tam
		var mundo_z: float = (celda.y + 0.5) * tam
		var rel: Vector3 = Vector3(mundo_x, 0.0, mundo_z) - jugador.global_position
		var local: Vector3 = jugador.global_transform.basis.inverse() * rel
		var p: Vector2 = Vector2(local.x, local.z) / alcance * radio
		if p.length() < radio:
			puntos.append(centro + p)
	if puntos.size() >= 2:
		for i in range(puntos.size() - 1):
			draw_line(puntos[i], puntos[i + 1], COLOR_RUTA, 2.0)


# Modo DIJKSTRA: ruta del enemigo hacia el jugador (la calcula el propio enemigo con Dijkstra).
func _dibujar_ruta_enemigo(centro: Vector2, radio: float) -> void:
	if not _es_dijkstra() or jugador == null:
		return
	var enemigo := objetivo as EnemigoPerseguidor
	if enemigo == null or not is_instance_valid(enemigo) or enemigo.ruta.size() < 2:
		return
	# ruta[0] es la celda del enemigo y la última la del jugador: se sustituyen por sus
	# posiciones reales para que la línea nazca en el enemigo y termine en el jugador.
	var pts: Array[Vector3] = [enemigo.global_position]
	for i in range(1, enemigo.ruta.size() - 1):
		pts.append(mapa_ref.celda_a_mundo(enemigo.ruta[i]))
	pts.append(jugador.global_position)
	_trazar(pts, centro, radio, COLOR_RUTA_ENEMIGO, 2.0)


# Texto bajo el radar: pasos hasta la salida, pasos del enemigo hacia ti y recordatorio de la tecla Z.
func _dibujar_info_dijkstra() -> void:
	if not _es_dijkstra():
		return
	var enemigo := objetivo as EnemigoPerseguidor
	var pasos_salida: int = maxi(0, mapa_ref.ruta_jugador.size() - 1)
	var pasos_enemigo: int = 0
	if enemigo != null and is_instance_valid(enemigo):
		pasos_enemigo = maxi(0, enemigo.ruta.size() - 1)
	var fuente: Font = ThemeDB.fallback_font
	var y: float = size.y + 16.0
	for linea in [
		[COLOR_RUTA_JUGADOR, "Salida: %d pasos" % pasos_salida],
		[COLOR_RUTA_ENEMIGO, "Enemigo: %d pasos" % pasos_enemigo],
		[Color(0.85, 0.9, 1.0), "Z · ver grafo"],
	]:
		draw_string_outline(fuente, Vector2(0.0, y), linea[1], HORIZONTAL_ALIGNMENT_RIGHT,
			size.x, 14, 4, Color(0.0, 0.0, 0.0, 0.9))
		draw_string(fuente, Vector2(0.0, y), linea[1], HORIZONTAL_ALIGNMENT_RIGHT,
			size.x, 14, linea[0])
		y += 18.0


# Posición de un punto del mundo en el radar (relativa al centro, sin recortar al círculo).
func _a_radar(pos_mundo: Vector3, radio: float) -> Vector2:
	var local: Vector3 = jugador.global_transform.basis.inverse() * (pos_mundo - jugador.global_position)
	return Vector2(local.x, local.z) / alcance * radio


func _trazar(puntos: Array[Vector3], centro: Vector2, radio: float, color: Color, grosor: float) -> void:
	var anterior: Vector2 = _a_radar(puntos[0], radio)
	for i in range(1, puntos.size()):
		var actual: Vector2 = _a_radar(puntos[i], radio)
		_segmento_en_circulo(centro, anterior, actual, radio, color, grosor)
		anterior = actual


# Dibuja solo la parte del segmento a-b (relativo al centro) que cae dentro del círculo del radar.
func _segmento_en_circulo(centro: Vector2, a: Vector2, b: Vector2, radio: float, color: Color, grosor: float) -> void:
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
	draw_line(centro + a + d * t0, centro + a + d * t1, color, grosor, true)
