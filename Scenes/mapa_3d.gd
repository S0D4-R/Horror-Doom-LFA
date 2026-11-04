class_name Mapa3D
extends Node3D
# Construye en 3D un mapa de muros y pasillos a partir de un .txt de unos y ceros.
#
# SALIDA ESTRATÉGICA
# ──────────────────
# La salida se elige para que sea:
#   • Lejos del jugador (distancia Dijkstra máxima posible, ≥ 60 % del mapa)
#   • No trivialmente visible desde el inicio
#   • Accesible pero no obvia: en un corredor de baja conectividad
# Las posiciones candidatas se computan con _elegir_salida_estrategica() en _ready().
# Si el mapa ya trae salida en el .txt con una posición buena, se respeta; de lo contrario
# se reemplaza por la calculada.
#
# MODO VICTORIA
# ─────────────
# El jugador gana al entrar en la celda de la salida. El HUD muestra una pantalla de victoria.

@export_file("*.txt") var archivo_mapa: String = "res://Maps/mapa2_cementerio.txt"
@export var tam_celda: float = 2.0
@export var alto_muro: float = 3.0
@export var camara_cenital: bool = false
@export var solo_escenografia: bool = false
@export var con_techo: bool = true
@export var semilla: int = 0

# Fuerza la salida que viene en el .txt en lugar de calcular una estratégica.
# Pon esto a true si ya ajustaste la salida a mano en el .txt y no quieres que se mueva.
@export var respetar_salida_txt: bool = false

var matriz: Array = []
var jugador: Vector2i
var salida: Vector2i
var enemigo: Vector2i
var jugador_nodo: Jugador
var modo: int = Partida.Modo.U_R_D4MN3D
var enemigo_nodo: EnemigoPerseguidor
var hud: HUD
var _env: Environment
var posiciones_perks: Dictionary = {}

# Modo DIJKSTRA: camino más corto del jugador a la salida. Se recalcula cada vez que el
# jugador cambia de celda y lo usan el radar 2D y la vista del grafo (tecla Z).
var ruta_jugador: Array[Vector2i] = []

var _snd_mapa: AudioStreamPlayer

# Distancia mínima (nodos Dijkstra) que debe tener la salida desde el jugador inicial.
# Se intenta maximizar; este valor es el umbral mínimo aceptable.
const SALIDA_DIST_MIN: int = 40


func _ready() -> void:
	if Partida.activa and not solo_escenografia:
		archivo_mapa = Partida.archivo_mapa()
		modo = Partida.modo
	print("Modo: %s | Mapa: %s" % [Partida.MODOS[modo]["nombre"], archivo_mapa])
	var datos := Grafo.cargar(archivo_mapa)
	matriz = datos["matriz"]
	jugador = datos["jugador"]
	salida = datos["salida"]
	enemigo = datos["enemigo"]
	if matriz.is_empty():
		return

	# Calcular una salida estratégica (si no se pide respetar la del .txt)
	if not respetar_salida_txt and _hay_salida():
		salida = _elegir_salida_estrategica()

	_construir_muros()
	_construir_suelo_y_techo()
	if solo_escenografia:
		return
	if _hay_salida():
		_marcador(salida, Color(0.2, 0.4, 1.0))

	enemigo_nodo = EnemigoPerseguidor.new()
	enemigo_nodo.mapa = self
	enemigo_nodo.calcular_ruta_siempre = es_dijkstra()   # su ruta se dibuja en el radar y en el grafo
	enemigo_nodo.position = celda_a_mundo(enemigo)
	add_child(enemigo_nodo)

	_colocar_perks()
	if camara_cenital:
		_marcador(jugador, Color(0.1, 0.9, 0.2))
		_agregar_camara_cenital()
	else:
		_agregar_ambiente()
		_agregar_jugador()
		enemigo_nodo.jugador = jugador_nodo
		enemigo_nodo.alcanzo_jugador.connect(_on_jugador_atrapado)

	_iniciar_audio_mapa()
	print("Salida estratégica en: %s" % salida)


# ── Salida estratégica ───────────────────────────────────────────────────────
# Criterios (en orden de prioridad):
#   1. La ruta Dijkstra desde el jugador sea lo más larga posible (difícil de llegar).
#   2. La ruta Dijkstra desde el enemigo sea >= la del jugador - 5 (no trivialmente bloqueada).
#   3. La celda tenga exactamente 2 vecinos libres (corredor estrecho, no encrucijada).
#   4. No esté a menos de 3 celdas de cualquier borde del mapa.
func _elegir_salida_estrategica() -> Vector2i:
	var filas: int = matriz.size()
	var cols: int = matriz[0].size()

	# Distancias Dijkstra desde el jugador y desde el enemigo (grafo inverso)
	var dist_jugador: Dictionary = _dijkstra_distancias(jugador)
	var dist_enemigo: Dictionary = _dijkstra_distancias(enemigo)

	# Recopilar candidatos: celdas libres que no son la posición inicial del jugador
	var candidatos: Array = []
	for y in filas:
		for x in cols:
			if matriz[y][x] != 0:
				continue
			var c := Vector2i(x, y)
			if c == jugador or c == enemigo:
				continue
			# Borde mínimo de 3 celdas
			if x < 3 or y < 3 or x >= cols - 3 or y >= filas - 3:
				continue
			if not dist_jugador.has(c):
				continue
			var dj: int = dist_jugador[c]
			if dj < SALIDA_DIST_MIN:
				continue
			var de: int = dist_enemigo.get(c, 999)
			# Vecinos libres (conectividad del corredor)
			var vecinos_libres: int = 0
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var n: Vector2i = c + d
				if n.y >= 0 and n.y < filas and n.x >= 0 and n.x < cols and matriz[n.y][n.x] == 0:
					vecinos_libres += 1
			candidatos.append({"celda": c, "dj": dj, "de": de, "vec": vecinos_libres})

	if candidatos.is_empty():
		# Fallback: usar la salida original del .txt
		return salida

	# Ordenar: maximizar dj, preferir vec == 2 (corredor), penalizar si de < dj - 5
	candidatos.sort_custom(func(a, b):
		var score_a: int = a["dj"] * 2 + (10 if a["vec"] == 2 else 0) - (20 if a["de"] < a["dj"] - 5 else 0)
		var score_b: int = b["dj"] * 2 + (10 if b["vec"] == 2 else 0) - (20 if b["de"] < b["dj"] - 5 else 0)
		return score_a > score_b
	)
	return candidatos[0]["celda"]


# BFS/Dijkstra de distancias (peso uniforme) desde una celda origen.
func _dijkstra_distancias(origen: Vector2i) -> Dictionary:
	var dist: Dictionary = {}
	var cola: Array = [[0, origen]]
	dist[origen] = 0
	var filas: int = matriz.size()
	var cols: int = matriz[0].size()
	while not cola.is_empty():
		cola.sort_custom(func(a, b): return a[0] < b[0])
		var actual = cola.pop_front()
		var d: int = actual[0]
		var c: Vector2i = actual[1]
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n: Vector2i = c + dir
			if n.y < 0 or n.y >= filas or n.x < 0 or n.x >= cols:
				continue
			if matriz[n.y][n.x] != 0:
				continue
			var nd: int = d + 1
			if not dist.has(n) or nd < dist[n]:
				dist[n] = nd
				cola.append([nd, n])
	return dist


# ── Victoria ─────────────────────────────────────────────────────────────────

func _on_jugador_llego_a_salida() -> void:
	print("¡Jugador escapó!")
	# Pausar al enemigo
	if enemigo_nodo != null and enemigo_nodo.has_method("congelar"):
		enemigo_nodo.congelar(true)
	if hud != null:
		hud._mostrar_victoria()
	# Esperar 3 segundos y volver al menú
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file(Partida.ESCENA_MENU)


# ── Resto del código (sin cambios funcionales) ───────────────────────────────

func celda_a_mundo(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * tam_celda, 0.0, (c.y + 0.5) * tam_celda)


# Hay salida en todos los modos salvo SUPERVIVENCIA.
func _hay_salida() -> bool:
	return modo != Partida.Modo.SUPERVIVENCIA


func es_dijkstra() -> bool:
	return modo == Partida.Modo.DIJKSTRA


# Dijkstra desde la celda del jugador hasta la salida (la usan el radar y la vista del grafo).
func _recalcular_ruta_jugador() -> void:
	if jugador_nodo != null:
		ruta_jugador = Grafo.dijkstra(matriz, jugador_nodo.celda_actual, salida)


func _es_visible(x: int, y: int) -> bool:
	var cols: int = matriz[0].size()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx: int = x + dx
			var ny: int = y + dy
			if ny >= 0 and ny < matriz.size() and nx >= 0 and nx < cols:
				if matriz[ny][nx] == 0:
					return true
	return false


func _construir_muros() -> void:
	var mat := _material(Color(0.55, 0.55, 0.6))
	var cols: int = matriz[0].size()
	for y in matriz.size():
		var x: int = 0
		while x < cols:
			if matriz[y][x] == 1 and _es_visible(x, y):
				var inicio: int = x
				while x < cols and matriz[y][x] == 1 and _es_visible(x, y):
					x += 1
				var largo: int = x - inicio
				_crear_bloque(
					Vector3((inicio + largo / 2.0) * tam_celda, alto_muro / 2.0, (y + 0.5) * tam_celda),
					Vector3(largo * tam_celda, alto_muro, tam_celda),
					mat, true)
			else:
				x += 1


func _construir_suelo_y_techo() -> void:
	var ancho: float = matriz[0].size() * tam_celda
	var largo: float = matriz.size() * tam_celda
	_crear_bloque(Vector3(ancho / 2.0, -0.1, largo / 2.0), Vector3(ancho, 0.2, largo),
		_material(Color(0.12, 0.12, 0.14)), true)
	if con_techo and not camara_cenital:
		_crear_bloque(Vector3(ancho / 2.0, alto_muro + 0.1, largo / 2.0), Vector3(ancho, 0.2, largo),
			_material(Color(0.08, 0.08, 0.09)), false)


func _crear_bloque(pos: Vector3, tam: Vector3, mat: Material, con_colision: bool) -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.position = pos
	var malla := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = tam
	malla.mesh = caja
	malla.material_override = mat
	cuerpo.add_child(malla)
	if con_colision:
		var col := CollisionShape3D.new()
		var forma := BoxShape3D.new()
		forma.size = tam
		col.shape = forma
		cuerpo.add_child(col)
	add_child(cuerpo)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _marcador(c: Vector2i, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = tam_celda * 0.3
	esfera.height = tam_celda * 0.6
	var mat := _material(color)
	mat.emission_enabled = true
	mat.emission = color
	m.mesh = esfera
	m.material_override = mat
	m.position = celda_a_mundo(c) + Vector3(0.0, tam_celda * 0.3, 0.0)
	add_child(m)
	return m


func _agregar_jugador() -> void:
	jugador_nodo = Jugador.new()
	jugador_nodo.tam_celda = tam_celda
	jugador_nodo.position = celda_a_mundo(jugador)
	jugador_nodo.celda_actual = jugador
	jugador_nodo.enemigo = enemigo_nodo
	jugador_nodo.efectos_cercania = (modo == Partida.Modo.U_R_D4MN3D)
	add_child(jugador_nodo)
	jugador_nodo.ventana_huida_iniciada.connect(_congelar_enemigo.bind(true))
	jugador_nodo.ventana_huida_terminada.connect(_congelar_enemigo.bind(false))
	# Detectar cuando el jugador llega a la salida
	jugador_nodo.celda_cambiada.connect(_on_celda_cambiada)
	# El autómata del enemigo reacciona a cada paso (cambio de celda) del jugador
	jugador_nodo.celda_cambiada.connect(enemigo_nodo.registrar_movimiento_jugador)
	if es_dijkstra():
		_recalcular_ruta_jugador()
	hud = HUD.new()
	add_child(hud)
	hud.conectar(jugador_nodo, enemigo_nodo)
	# Mapa de pasos del autómata y del jugador (tecla K, no pausa el juego)
	var mapa_pasos := MapaPasos.new()
	add_child(mapa_pasos)
	mapa_pasos.conectar(self, jugador_nodo, enemigo_nodo)


func _on_celda_cambiada(celda: Vector2i) -> void:
	if es_dijkstra():   # el camino más corto a la salida sigue al jugador
		_recalcular_ruta_jugador()
	if celda == salida:
		_on_jugador_llego_a_salida()


func _agregar_ambiente() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.4)
	env.ambient_light_energy = 0.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.03, 0.04)
	env.fog_density = 0.08
	var we := WorldEnvironment.new()
	we.environment = env
	_env = env
	add_child(we)


func _agregar_camara_cenital() -> void:
	var ancho: float = matriz[0].size() * tam_celda
	var largo: float = matriz.size() * tam_celda
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(largo, ancho / 1.78) * 1.05
	cam.position = Vector3(ancho / 2.0, alto_muro * 4.0, largo / 2.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(cam)
	cam.current = true
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-70.0, 30.0, 0.0)
	add_child(luz)


func _iniciar_audio_mapa() -> void:
	var nombre_base: String = archivo_mapa.get_file().get_basename()
	_snd_mapa = Sonidos.crear_bucle(self, nombre_base, -8.0)
	if _snd_mapa != null:
		_snd_mapa.play()


const INTERVALO_REGENERACION: float = 20.0

var _rng := RandomNumberGenerator.new()
var _celdas_libres: Array[Vector2i] = []
var _perks_en_mapa: Dictionary = {}
var _regenerando: bool = false
var _t_regeneracion: float = 0.0


func _distancia(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _celda_de(nodo: Node3D) -> Vector2i:
	return Vector2i(floori(nodo.global_position.x / tam_celda), floori(nodo.global_position.z / tam_celda))


# Tipos de perk que aparecen en este modo. En DIJKSTRA el radar ya está siempre activo,
# así que no tiene sentido generar el perk de radar.
func _tipos_perk() -> Array:
	var tipos: Array = Perks.todos().duplicate()
	if es_dijkstra():
		tipos.erase(Perks.Tipo.RADAR)
	return tipos


func _colocar_perks() -> void:
	if semilla == 0:
		_rng.randomize()
	else:
		_rng.seed = semilla
	for y in matriz.size():
		for x in matriz[y].size():
			if matriz[y][x] == 0:
				_celdas_libres.append(Vector2i(x, y))
	for tipo in _tipos_perk():
		_crear_perk(tipo, _buscar_celda(jugador, enemigo))


func _crear_perk(tipo: int, celda: Vector2i) -> void:
	var item := PerkItem.new()
	item.tipo = tipo
	item.position = celda_a_mundo(celda)
	item.recogido.connect(_on_perk_tomado)
	add_child(item)
	_perks_en_mapa[tipo] = item
	posiciones_perks[tipo] = celda
	print("Perk %s en la celda %s" % [Perks.nombre(tipo), celda])


func _on_perk_tomado(tipo: int) -> void:
	_perks_en_mapa.erase(tipo)
	posiciones_perks.erase(tipo)
	if _perks_en_mapa.is_empty() and not _regenerando:
		_regenerando = true
		_t_regeneracion = INTERVALO_REGENERACION


func _regenerar_uno() -> void:
	var faltan: Array = []
	for tipo in _tipos_perk():
		if not _perks_en_mapa.has(tipo):
			faltan.append(tipo)
	if faltan.is_empty():
		_regenerando = false
		return
	var elegido: int = faltan[_rng.randi_range(0, faltan.size() - 1)]
	var c_jugador: Vector2i = jugador_nodo.celda_actual if jugador_nodo != null else jugador
	var c_enemigo: Vector2i = _celda_de(enemigo_nodo) if enemigo_nodo != null else enemigo
	_crear_perk(elegido, _buscar_celda(c_jugador, c_enemigo))
	if _perks_en_mapa.size() >= _tipos_perk().size():
		_regenerando = false


func _barajar_celdas() -> void:
	for i in range(_celdas_libres.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Vector2i = _celdas_libres[i]
		_celdas_libres[i] = _celdas_libres[j]
		_celdas_libres[j] = tmp


func _buscar_celda(c_jugador: Vector2i, c_enemigo: Vector2i) -> Vector2i:
	_barajar_celdas()
	var ocupadas: Array[Vector2i] = []
	for tipo in _perks_en_mapa:
		ocupadas.append(posiciones_perks[tipo])
	for factor in [1.0, 0.6, 0.3, 0.0]:
		for c in _celdas_libres:
			if _distancia(c, c_jugador) < 10 * factor or _distancia(c, salida) < 6 * factor \
					or _distancia(c, c_enemigo) < 6 * factor:
				continue
			var cerca: bool = false
			for e in ocupadas:
				if _distancia(c, e) < 15 * factor:
					cerca = true
					break
			if not cerca:
				return c
	return _celdas_libres[0]


func _congelar_enemigo(valor: bool) -> void:
	if enemigo_nodo == null:
		return
	if enemigo_nodo.has_method("congelar"):
		enemigo_nodo.congelar(valor)


# El enemigo te alcanzó: sin respawn → game-over (lo maneja el HUD vía jugador.morir()).
func _on_jugador_atrapado() -> void:
	print("¡Abaddon te atrapó!")
	# No recargar escena: la señal jugador_muerto ya activó el game-over en el HUD.


# ── Easter eggs ──────────────────────────────────────────────────────────────
#
# Código Konami  →  W W S S A D A D  clic-izq  clic-der
#   Efecto: teletransporta al jugador a la salida (fin del mapa).
#
# Código Lluvia  →  A D  clic-der  clic-der
#   Efecto: spawnea todos los ítems faltantes junto al jugador.

# Cada entrada se codifica como un carácter: W=U  S=D  A=L  D=R  clic-izq=A  clic-der=B
const _EE_KONAMI: String = "UUDDLRLRAB"
const _EE_LLUVIA: String = "LRBB"

var _ee_buffer: String = ""   # historial de las últimas entradas (máx longitud del código más largo)
const _EE_MAX: int = 10       # = len(_EE_KONAMI)


func _ee_registrar(c: String) -> void:
	_ee_buffer += c
	if _ee_buffer.length() > _EE_MAX:
		_ee_buffer = _ee_buffer.right(_EE_MAX)
	if _ee_buffer.ends_with(_EE_KONAMI):
		_ee_buffer = ""
		_activar_konami()
	elif _ee_buffer.ends_with(_EE_LLUVIA):
		_ee_buffer = ""
		_activar_lluvia()


func _activar_konami() -> void:
	if jugador_nodo == null or jugador_nodo.esta_muerto:
		return
	print("[EasterEgg] Konami activado → teletransporte a la salida")
	# Congelar al enemigo un momento para que no mate al jugador mientras aparece en la salida
	_congelar_enemigo(true)
	jugador_nodo.global_position = celda_a_mundo(salida) + Vector3(0.0, 0.1, 0.0)
	jugador_nodo.celda_actual = salida
	# Flash visual de confirmación a través del HUD
	if hud != null and hud.has_method("_mostrar"):
		hud._mostrar("✦ WARP ✦")
	Sonidos.reproducir(jugador_nodo, "ui_comenzar")
	# Tras medio segundo descongelar y dejar que el jugador toque la celda de salida normalmente
	await get_tree().create_timer(0.5).timeout
	_congelar_enemigo(false)
	# Activar la condición de victoria manualmente
	_on_celda_cambiada(salida)


func _activar_lluvia() -> void:
	if jugador_nodo == null or jugador_nodo.esta_muerto:
		return
	print("[EasterEgg] Lluvia de ítems activada")
	var c_jugador: Vector2i = jugador_nodo.celda_actual
	# Spawnear todos los tipos que no estén ya en el mapa, justo al lado del jugador
	# Celdas adyacentes al jugador en espiral (cerca primero)
	var adyacentes: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	]
	var ocupadas_spawn: Array[Vector2i] = []
	for v in posiciones_perks.values():
		ocupadas_spawn.append(v)
	for tipo in _tipos_perk():
		if _perks_en_mapa.has(tipo):
			continue
		var celda_spawn: Vector2i = c_jugador
		for off in adyacentes:
			var candidata: Vector2i = c_jugador + off
			if candidata.y >= 0 and candidata.y < matriz.size() \
					and candidata.x >= 0 and candidata.x < matriz[candidata.y].size() \
					and matriz[candidata.y][candidata.x] == 0 \
					and not ocupadas_spawn.has(candidata):
				celda_spawn = candidata
				ocupadas_spawn.append(celda_spawn)
				break
		_crear_perk(tipo, celda_spawn)
	if hud != null and hud.has_method("_mostrar"):
		hud._mostrar("✦ ITEMS ✦")
	Sonidos.reproducir(jugador_nodo, "recoger_item")


# ESC, R y M (pausa, reintentar y volver al menú tras morir) los maneja el HUD.

# _input (no _unhandled_input) para recibir las teclas antes de que jugador.gd las consuma.
func _input(event: InputEvent) -> void:
	if jugador_nodo != null and jugador_nodo.esta_muerto:
		return
	# Solo el primer frame de la pulsación (pressed=true, echo=false)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_W: _ee_registrar("U")
			KEY_S: _ee_registrar("D")
			KEY_A: _ee_registrar("L")
			KEY_D: _ee_registrar("R")
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:  _ee_registrar("A")
			MOUSE_BUTTON_RIGHT: _ee_registrar("B")


const NIEBLA_BASE: float = 0.08
const NIEBLA_CERCA: float = 0.16


func _process(delta: float) -> void:
	if _env != null and jugador_nodo != null:
		_env.fog_density = lerpf(NIEBLA_BASE, NIEBLA_CERCA, jugador_nodo.cercania)
	if _regenerando:
		_t_regeneracion -= delta
		if _t_regeneracion <= 0.0:
			_t_regeneracion = INTERVALO_REGENERACION
			_regenerar_uno()
