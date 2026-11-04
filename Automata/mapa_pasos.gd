class_name MapaPasos
extends CanvasLayer
# ─── Mapa de pasos (tecla K) ──────────────────────────────────────────────────
# Superposición que dibuja el recorrido del autómata (Abaddon, línea roja) y del jugador
# (línea azul), más el estado actual del autómata y su historial de transiciones.
#
#   • NO muestra el mapa completo: solo las celdas que el jugador ya recorrió y los muros
#     pegados a ellas (radio_vision_celdas). Lo demás queda oculto (niebla de exploración).
#   • El recorrido de Abaddon (sus pasos) se dibuja completo.
#
#   • K abre / cierra el mapa. NO pausa el juego: todo sigue corriendo.
#   • Mientras está abierto, Abaddon se mueve más lento (factor_velocidad_enemigo).
#   • Los recorridos se van guardando siempre (aunque el mapa esté cerrado), así que al
#     abrirlo se ve todo lo que ya pasó.
#   • Con el menú de pausa (ESC) o en Game Over el mapa se oculta solo.
#
# Cableado (lo hace mapa_3d.gd):  MapaPasos.new() → add_child → conectar(mapa, jugador, enemigo)

const COLOR_FONDO := Color(0.02, 0.02, 0.03, 0.84)
const COLOR_BORDE := Color(0.45, 0.12, 0.10)
const COLOR_PISO := Color(0.07, 0.07, 0.09)
const COLOR_VISITADA := Color(0.14, 0.14, 0.19)   # celdas por las que el jugador ya pasó
const COLOR_MURO := Color(0.32, 0.32, 0.38)
const COLOR_ENEMIGO := Color(1.0, 0.18, 0.12)
const COLOR_JUGADOR := Color(0.25, 0.55, 1.0)
const COLOR_SALIDA := Color(0.2, 1.0, 0.3)
const COLOR_TEXTO := Color(0.92, 0.92, 0.92)
const COLOR_TEXTO_SUAVE := Color(0.6, 0.6, 0.65)

const MAX_PUNTOS: int = 4000            # máximo de celdas guardadas por recorrido
const MAX_TRANSICIONES: int = 7         # transiciones que se muestran en el panel lateral
const ANCHO_PANEL_LATERAL: float = 270.0
const MARGEN_INFERIOR: float = 96.0     # deja libre la barra del HUD

@export var tecla: Key = KEY_K
# 0.6 = Abaddon va al 60 % de su velocidad mientras el mapa está abierto.
@export var factor_velocidad_enemigo: float = 0.6
# Cuántas celdas alrededor de cada celda recorrida se revelan (1 = los muros pegados al pasillo).
@export var radio_vision_celdas: int = 1

var abierto: bool = false

var _mapa: Mapa3D
var _jugador: Jugador
var _enemigo: EnemigoPerseguidor
var _camino_jugador: Array[Vector2i] = []
var _camino_enemigo: Array[Vector2i] = []
var _transiciones: Array = []           # cada entrada: [estado_anterior, estado_nuevo, evento]
var _visitadas: Dictionary = {}         # celdas por las que pasó el jugador
var _reveladas: Dictionary = {}         # celdas visibles en el mapa (visitadas + alrededor)
var _lienzo: Control
var _fuente: Font

# Geometría del mapa dibujado (se recalcula en cada _dibujar)
var _origen: Vector2 = Vector2.ZERO
var _px: float = 1.0


func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS   # para poder ocultarse cuando el juego está en pausa
	_fuente = ThemeDB.fallback_font
	_lienzo = Control.new()
	_lienzo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lienzo.visible = false
	add_child(_lienzo)
	_lienzo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lienzo.draw.connect(_dibujar)


func conectar(mapa: Mapa3D, jugador: Jugador, enemigo: EnemigoPerseguidor) -> void:
	_mapa = mapa
	_jugador = jugador
	_enemigo = enemigo
	_camino_jugador.append(mapa.jugador)    # celda inicial del jugador
	_revelar(mapa.jugador)
	_camino_enemigo.append(mapa.enemigo)    # celda inicial del enemigo
	jugador.celda_cambiada.connect(_on_celda_jugador)
	enemigo.estado_cambiado.connect(_on_estado_cambiado)


# ── Entrada ──────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or _jugador == null or _jugador.esta_muerto:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == tecla:
		_poner_abierto(not abierto)


func _poner_abierto(valor: bool) -> void:
	abierto = valor
	if _enemigo != null:
		_enemigo.set_factor_velocidad(factor_velocidad_enemigo if abierto else 1.0)


# ── Registro de recorridos ───────────────────────────────────────────────────
func _on_celda_jugador(celda: Vector2i) -> void:
	_registrar(_camino_jugador, celda)


func _on_estado_cambiado(anterior: int, nuevo: int, evento: int) -> void:
	_transiciones.append([anterior, nuevo, evento])
	if _transiciones.size() > 50:
		_transiciones.remove_at(0)


# Marca la celda como recorrida y revela las de alrededor.
func _revelar(celda: Vector2i) -> void:
	_visitadas[celda] = true
	var r: int = maxi(0, radio_vision_celdas)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c: Vector2i = celda + Vector2i(dx, dy)
			if c.y >= 0 and c.y < _mapa.matriz.size() and c.x >= 0 and c.x < _mapa.matriz[c.y].size():
				_reveladas[c] = true


func _registrar(camino: Array[Vector2i], celda: Vector2i) -> void:
	if camino.is_empty() or camino[camino.size() - 1] != celda:
		camino.append(celda)
		if camino.size() > MAX_PUNTOS:
			camino.remove_at(0)


func _process(_delta: float) -> void:
	if _enemigo == null or _jugador == null:
		return
	var en_pausa: bool = get_tree().paused
	if abierto and _jugador.esta_muerto:
		_poner_abierto(false)
	# Se consulta cada frame (así también cuenta si el jugador se teletransporta).
	if not _visitadas.has(_jugador.celda_actual):
		_revelar(_jugador.celda_actual)
	if not en_pausa:
		# El enemigo no emite señal al cambiar de celda, así que se consulta cada frame.
		_registrar(_camino_enemigo, _enemigo.celda_actual())
	_lienzo.visible = abierto and not en_pausa
	if _lienzo.visible:
		_lienzo.queue_redraw()


# ── Dibujo ───────────────────────────────────────────────────────────────────
func _dibujar() -> void:
	if _mapa == null or _mapa.matriz.is_empty():
		return
	var vp: Vector2 = _lienzo.size
	var marco := Rect2(Vector2(24.0, 24.0), Vector2(vp.x - 48.0, vp.y - 48.0 - MARGEN_INFERIOR))
	if marco.size.x < 320.0 or marco.size.y < 160.0:
		return

	_lienzo.draw_rect(marco, COLOR_FONDO)
	_lienzo.draw_rect(marco, COLOR_BORDE, false, 2.0)
	_texto("MAPA DE PASOS", marco.position + Vector2(16.0, 30.0), 22, COLOR_ENEMIGO)
	_texto("[K] cerrar", Vector2(marco.end.x - 100.0, marco.position.y + 28.0), 14, COLOR_TEXTO_SUAVE)

	# Área donde cabe el mapa (a la izquierda del panel lateral)
	var area := Rect2(marco.position + Vector2(12.0, 46.0),
		Vector2(marco.size.x - 24.0 - ANCHO_PANEL_LATERAL, marco.size.y - 58.0))
	var filas: int = _mapa.matriz.size()
	var cols: int = 0
	for fila in _mapa.matriz:
		cols = maxi(cols, fila.size())
	_px = minf(area.size.x / float(cols), area.size.y / float(filas))
	_origen = area.position + (area.size - Vector2(cols, filas) * _px) * 0.5

	_dibujar_laberinto(filas, cols)
	_dibujar_caminos()
	_dibujar_marcadores()
	_dibujar_panel_lateral(Rect2(Vector2(marco.end.x - ANCHO_PANEL_LATERAL, marco.position.y + 46.0),
		Vector2(ANCHO_PANEL_LATERAL - 12.0, marco.size.y - 58.0)))


func _dibujar_laberinto(filas: int, cols: int) -> void:
	# Solo el contorno del área total: da la escala sin revelar el contenido.
	_lienzo.draw_rect(Rect2(_origen, Vector2(cols, filas) * _px), Color(COLOR_BORDE, 0.45), false, 1.0)
	var lado: float = _px + 0.5   # un poco más grande para que no queden rendijas entre celdas
	for k in _reveladas:
		var c: Vector2i = k
		var color: Color = COLOR_PISO
		if _mapa.matriz[c.y][c.x] == 1:
			color = COLOR_MURO
		elif _visitadas.has(c):
			color = COLOR_VISITADA
		_lienzo.draw_rect(Rect2(_origen + Vector2(c) * _px, Vector2(lado, lado)), color)


func _dibujar_caminos() -> void:
	_trazar(_camino_enemigo, COLOR_ENEMIGO, 3.0)
	_trazar(_camino_jugador, COLOR_JUGADOR, 2.0)


# Dibuja un recorrido como polilínea. Si dos celdas consecutivas no son vecinas (por ejemplo
# tras un teletransporte) corta la línea en vez de atravesar el mapa.
func _trazar(camino: Array[Vector2i], color: Color, ancho: float) -> void:
	var tramo := PackedVector2Array()
	var previo := Vector2i.ZERO
	for c in camino:
		if not tramo.is_empty() and absi(c.x - previo.x) + absi(c.y - previo.y) > 1:
			if tramo.size() >= 2:
				_lienzo.draw_polyline(tramo, color, ancho, true)
			tramo = PackedVector2Array()
		tramo.append(_centro_celda(c))
		previo = c
	if tramo.size() >= 2:
		_lienzo.draw_polyline(tramo, color, ancho, true)


func _dibujar_marcadores() -> void:
	var r: float = maxf(_px * 0.9, 4.0)
	# Salida (solo existe en el modo con salida y solo se ve si el jugador ya la descubrió)
	if _mapa.modo == Partida.Modo.U_R_D4MN3D and _reveladas.has(_mapa.salida):
		var cs: Vector2 = _centro_celda(_mapa.salida)
		_lienzo.draw_rect(Rect2(cs - Vector2(r, r), Vector2(r, r) * 2.0), COLOR_SALIDA)
	# Puntos de inicio (círculo hueco)
	if not _camino_enemigo.is_empty():
		_lienzo.draw_arc(_centro_celda(_camino_enemigo[0]), r * 0.8, 0.0, TAU, 20, COLOR_ENEMIGO, 1.5)
	if not _camino_jugador.is_empty():
		_lienzo.draw_arc(_centro_celda(_camino_jugador[0]), r * 0.8, 0.0, TAU, 20, COLOR_JUGADOR, 1.5)
	# Posiciones actuales (usan la posición real, así se mueven suaves dentro de la celda)
	_punto_actual(_enemigo.global_position, COLOR_ENEMIGO, r)
	_punto_actual(_jugador.global_position, COLOR_JUGADOR, r)


func _punto_actual(pos_mundo: Vector3, color: Color, r: float) -> void:
	var p: Vector2 = _origen + Vector2(pos_mundo.x, pos_mundo.z) / _mapa.tam_celda * _px
	_lienzo.draw_circle(p, r, color)
	_lienzo.draw_arc(p, r, 0.0, TAU, 20, Color.WHITE, 1.5)


func _dibujar_panel_lateral(rect: Rect2) -> void:
	var x: float = rect.position.x
	var y: float = rect.position.y + 4.0

	# Estado actual del autómata
	_texto("AUTÓMATA", Vector2(x, y + 14.0), 15, COLOR_TEXTO_SUAVE)
	y += 36.0
	_texto(_enemigo.nombre_estado(), Vector2(x, y), 22, COLOR_ENEMIGO)
	y += 30.0

	# Leyenda
	_lienzo.draw_line(Vector2(x, y - 5.0), Vector2(x + 28.0, y - 5.0), COLOR_ENEMIGO, 3.0)
	_texto("Abaddon (%d pasos)" % maxi(0, _camino_enemigo.size() - 1), Vector2(x + 38.0, y), 14, COLOR_TEXTO)
	y += 22.0
	_lienzo.draw_line(Vector2(x, y - 5.0), Vector2(x + 28.0, y - 5.0), COLOR_JUGADOR, 2.0)
	_texto("Jugador (%d pasos)" % maxi(0, _camino_jugador.size() - 1), Vector2(x + 38.0, y), 14, COLOR_TEXTO)
	y += 22.0
	_texto("Explorado: %d celdas" % _visitadas.size(), Vector2(x + 38.0, y), 14, COLOR_TEXTO)
	y += 22.0
	if _mapa.modo == Partida.Modo.U_R_D4MN3D and _reveladas.has(_mapa.salida):
		_lienzo.draw_rect(Rect2(Vector2(x + 8.0, y - 13.0), Vector2(12.0, 12.0)), COLOR_SALIDA)
		_texto("Salida", Vector2(x + 38.0, y), 14, COLOR_TEXTO)
		y += 22.0
	y += 14.0

	# Historial de transiciones (la más reciente arriba)
	_texto("TRANSICIONES", Vector2(x, y), 15, COLOR_TEXTO_SUAVE)
	y += 24.0
	if _transiciones.is_empty():
		_texto("(ninguna todavía)", Vector2(x, y), 13, COLOR_TEXTO_SUAVE)
		y += 20.0
	else:
		var mostradas: int = 0
		var i: int = _transiciones.size() - 1
		while i >= 0 and mostradas < MAX_TRANSICIONES:
			var t: Array = _transiciones[i]
			_texto("%s > %s" % [EnemigoPerseguidor.Estado.keys()[t[0]], EnemigoPerseguidor.Estado.keys()[t[1]]],
				Vector2(x, y), 14, COLOR_TEXTO)
			y += 17.0
			_texto("(%s)" % EnemigoPerseguidor.Evento.keys()[t[2]], Vector2(x + 10.0, y), 12, COLOR_TEXTO_SUAVE)
			y += 21.0
			mostradas += 1
			i -= 1

	# Aviso de velocidad, pegado al fondo del panel
	_texto("Abaddon al %d %% de velocidad" % int(factor_velocidad_enemigo * 100.0),
		Vector2(x, rect.end.y - 6.0), 12, COLOR_TEXTO_SUAVE)


# ── Utilidades ───────────────────────────────────────────────────────────────
func _centro_celda(c: Vector2i) -> Vector2:
	return _origen + (Vector2(c) + Vector2(0.5, 0.5)) * _px


func _texto(t: String, pos: Vector2, tam: int, color: Color) -> void:
	_lienzo.draw_string(_fuente, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, color)
