class_name Mapa3D
extends Node3D
# Construye en 3D un mapa de muros y pasillos a partir de un .txt de unos y ceros.
 
@export_file("*.txt") var archivo_mapa: String = "res://Maps/mapa2_cementerio.txt"
@export var tam_celda: float = 2.0   # metros por celda
@export var alto_muro: float = 3.0
@export var camara_cenital: bool = false   # true = vista desde arriba; false = primera persona
@export var solo_escenografia: bool = false   # true = solo muros y suelo (sin jugador, HUD ni perks): lo usa el menú 3D
@export var con_techo: bool = true   # false = cielo abierto (cementerio, ciudad)
@export var semilla: int = 0   # 0 = perks en posiciones distintas cada partida; otro número = siempre las mismas
 
var matriz: Array = []
var jugador: Vector2i
var salida: Vector2i
var enemigo: Vector2i
var jugador_nodo: Jugador
var modo: int = Partida.Modo.U_R_D4MN3D
var enemigo_nodo: Perseguidor
var hud: HUD
var _env: Environment
var posiciones_perks: Dictionary = {}   # tipo -> celda, útil para el informe
 
 
func _ready() -> void:
	if Partida.activa and not solo_escenografia:   # llegamos desde el menú: usar el mapa y el modo elegidos
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
	_construir_muros()
	_construir_suelo_y_techo()
	if solo_escenografia:
		return
	if modo == Partida.Modo.U_R_D4MN3D:   # en SUPERVIVENCIA no hay salida
		_marcador(salida, Color(0.2, 0.4, 1.0))
	enemigo_nodo = Perseguidor.new()
	enemigo_nodo.mapa = self
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
 
 
# Centro de una celda en coordenadas del mundo 3D (lo usarán el jugador y el enemigo).
func celda_a_mundo(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * tam_celda, 0.0, (c.y + 0.5) * tam_celda)
 
 
# Un muro solo se dibuja si toca (incluso en diagonal) alguna celda de piso.
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
 
 
# Une muros consecutivos de una fila en una sola caja para tener muchos menos nodos.
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
	if con_techo and not camara_cenital:   # en vista cenital el techo taparía todo
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
 
 
# Esfera de color provisional: azul = salida, rojo = enemigo, verde = jugador (solo en vista cenital).
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
	jugador_nodo.celda_actual = jugador   # así la celda inicial no cuenta como un paso
	jugador_nodo.enemigo = enemigo_nodo   # para medir la distancia al enemigo
	jugador_nodo.efectos_cercania = (modo == Partida.Modo.U_R_D4MN3D)   # efectos solo con un enemigo
	add_child(jugador_nodo)
	# Mientras dura la huida (colores invertidos) el enemigo se queda quieto.
	jugador_nodo.ventana_huida_iniciada.connect(_congelar_enemigo.bind(true))
	jugador_nodo.ventana_huida_terminada.connect(_congelar_enemigo.bind(false))
	hud = HUD.new()
	add_child(hud)
	hud.conectar(jugador_nodo, enemigo_nodo)
 
 
# Oscuridad casi total y niebla: la linterna del jugador es la luz principal.
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


# ---------- Perks en posiciones aleatorias, con regeneración ----------

const INTERVALO_REGENERACION: float = 20.0   # segundos entre un perk que reaparece y el siguiente

var _rng := RandomNumberGenerator.new()
var _celdas_libres: Array[Vector2i] = []
var _perks_en_mapa: Dictionary = {}   # tipo -> PerkItem disponible ahora mismo
var _regenerando: bool = false
var _t_regeneracion: float = 0.0


func _distancia(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)   # distancia Manhattan en celdas


func _celda_de(nodo: Node3D) -> Vector2i:
	return Vector2i(floori(nodo.global_position.x / tam_celda), floori(nodo.global_position.z / tam_celda))


# Coloca un perk de cada tipo en celdas libres al azar, lejos del jugador, la salida,
# el enemigo y los otros perks.
func _colocar_perks() -> void:
	if semilla == 0:
		_rng.randomize()
	else:
		_rng.seed = semilla
	for y in matriz.size():
		for x in matriz[y].size():
			if matriz[y][x] == 0:
				_celdas_libres.append(Vector2i(x, y))
	for tipo in Perks.todos():
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


# Cuando se toman TODOS los perks, empieza a reaparecer uno cada INTERVALO_REGENERACION segundos,
# y sigue así hasta que todos estén disponibles a la vez.
func _on_perk_tomado(tipo: int) -> void:
	_perks_en_mapa.erase(tipo)
	posiciones_perks.erase(tipo)
	if _perks_en_mapa.is_empty() and not _regenerando:
		_regenerando = true
		_t_regeneracion = INTERVALO_REGENERACION
		print("Todos los perks fueron tomados: empiezan a regenerarse")


func _regenerar_uno() -> void:
	var faltan: Array = []
	for tipo in Perks.todos():
		if not _perks_en_mapa.has(tipo):
			faltan.append(tipo)
	if faltan.is_empty():
		_regenerando = false
		return
	var elegido: int = faltan[_rng.randi_range(0, faltan.size() - 1)]
	var c_jugador: Vector2i = jugador_nodo.celda_actual if jugador_nodo != null else jugador
	var c_enemigo: Vector2i = _celda_de(enemigo_nodo) if enemigo_nodo != null else enemigo
	_crear_perk(elegido, _buscar_celda(c_jugador, c_enemigo))
	if _perks_en_mapa.size() >= Perks.todos().size():
		_regenerando = false
		print("Todos los perks están disponibles otra vez")


func _barajar_celdas() -> void:   # Fisher-Yates
	for i in range(_celdas_libres.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Vector2i = _celdas_libres[i]
		_celdas_libres[i] = _celdas_libres[j]
		_celdas_libres[j] = tmp


# Elige una celda libre lejos del jugador, la salida, el enemigo y los perks que ya están en el mapa.
# Si el mapa es chico, relaja las distancias poco a poco.
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


# Enemigo quieto durante la ventana de huida. El enemigo real solo necesita un método congelar(valor).
func _congelar_enemigo(valor: bool) -> void:
	if enemigo_nodo == null:
		return
	if enemigo_nodo.has_method("congelar"):
		enemigo_nodo.congelar(valor)
	elif enemigo_nodo is MeshInstance3D:   # marcador provisional: se ve azul mientras está congelado
		var mat := (enemigo_nodo as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null:
			var col: Color = Color(0.3, 0.55, 1.0) if valor else Color(1.0, 0.1, 0.1)
			mat.albedo_color = col
			mat.emission = col

# El enemigo te alcanzó sin escudo: se reinicia la partida.
func _on_jugador_atrapado() -> void:
	print("¡Te atrapó el enemigo!")
	get_tree().reload_current_scene.call_deferred()

# M = volver al menú principal.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		get_tree().change_scene_to_file(Partida.ESCENA_MENU)


# Cerca del enemigo la niebla se cierra y el radio de visión se reduce aún más.
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
