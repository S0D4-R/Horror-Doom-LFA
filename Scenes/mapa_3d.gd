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

@export_file("*.txt") var archivo_mapa: String = "res://Maps/mapa1_pasillos.txt"
@export var tam_celda: float = 2.0
@export var alto_muro: float = 3.0
@export var camara_cenital: bool = false
@export var solo_escenografia: bool = false
@export var con_techo: bool = true
@export var semilla: int = 0

@export_group("Texturas")
@export var usar_texturas: bool = true
@export var usar_normales: bool = false
@export var metros_por_textura: float = 2.0
@export var metros_por_textura_cielo: float = 48.0

# Fuerza la salida que viene en el .txt en lugar de calcular una estratégica.
@export var respetar_salida_txt: bool = false

var matriz: Array = []
var jugador: Vector2i
var salida: Vector2i
var enemigo: Vector2i
var fuente: Vector2i = Vector2i(-1, -1)
var tren_inicio: Vector2i = Vector2i(-1, -1)
var tren_largo: int = 0
var tren_orientacion: String = "h"
var es_exterior: bool = false
var altura_cielo: float = 18.0
var jugador_nodo: Jugador
var modo: int = Partida.Modo.U_R_D4MN3D
var enemigo_nodo: EnemigoPerseguidor
var hud: HUD
var _env: Environment
var posiciones_perks: Dictionary = {}

var ruta_jugador: Array[Vector2i] = []

var _mat_pared: StandardMaterial3D
var _mat_suelo: StandardMaterial3D
var _mat_techo: StandardMaterial3D
var _mat_lapida: StandardMaterial3D
var _mat_apt: Dictionary = {}
var _mat_nichos: Array[StandardMaterial3D] = []
var _mat_nicho_marco: StandardMaterial3D
var _mat_nicho_cruz: StandardMaterial3D
var _mat_nicho_repisa: StandardMaterial3D
var _mat_nicho_tejadillo: StandardMaterial3D
var _lotes: Dictionary = {}
var _cuerpo_muros: StaticBody3D
var _mat_metro_fondo: StandardMaterial3D
var _mat_metro_metal: StandardMaterial3D
var _mat_metro_poster_fondo: StandardMaterial3D
var _mat_metro_poster_panel: StandardMaterial3D

var _fuente_metro: Font
var _snd_mapa: AudioStreamPlayer

const SALIDA_DIST_MIN: int = 40

# ── Easter eggs ──────────────────────────────────────────────────────────────
# Konami: W W S S A D A D + clic izquierdo + clic derecho → teletransporte a la salida.
# Ítems:  izquierda derecha izquierda derecha + doble clic derecho → ítems cercanos.
const _EE_KONAMI: String = "UUDDLRLRAB"
const _EE_LLUVIA: String = "LRLRBB"
const _EE_LLUVIA_RATON: String = "ABABBB"
const _EE_MAX: int = 10
var _ee_buffer: String = ""
var _ee_ultimo_der_msec: int = -10000

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
	fuente = datos.get("fuente", Vector2i(-1, -1))
	tren_inicio = datos.get("tren", Vector2i(-1, -1))
	tren_largo = int(datos.get("tren_largo", 0))
	tren_orientacion = str(datos.get("tren_orientacion", "h"))
	es_exterior = str(datos.get("exterior", "0")) == "1"
	if _es_mapa_metro():
		alto_muro = maxf(alto_muro, 5.2)
	elif _es_mapa_plaza():
		alto_muro = maxf(alto_muro, 6.0)
	altura_cielo = maxf(alto_muro + 1.0, float(datos.get("altura_cielo", "0")))
	if matriz.is_empty():
		return

	# Calcular una salida estratégica (si no se pide respetar la del .txt)
	if not respetar_salida_txt and _hay_salida():
		salida = _elegir_salida_estrategica()

	_preparar_materiales()
	_construir_muros()
	_construir_suelo_y_techo()
	if _es_mapa_plaza():
		_construir_fuente()
		_construir_detalles_plaza()
	if _es_mapa_metro():
		_construir_tren()
		_construir_detalles_metro()
	_volcar_lotes()
	if solo_escenografia:
		return
	if _hay_salida():
		_marcador(salida, Color(0.2, 0.4, 1.0))

	enemigo_nodo = EnemigoPerseguidor.new()
	enemigo_nodo.mapa = self
	enemigo_nodo.calcular_ruta_siempre = es_dijkstra()
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
func _elegir_salida_estrategica() -> Vector2i:
	var filas: int = matriz.size()
	var cols: int = matriz[0].size()

	var dist_jugador: Dictionary = _dijkstra_distancias(jugador)
	var dist_enemigo: Dictionary = _dijkstra_distancias(enemigo)

	var ocultas: bool = _es_mapa_plaza() or _es_mapa_metro()
	var candidatos: Array = []
	for y in filas:
		for x in cols:
			if matriz[y][x] != 0:
				continue
			var c := Vector2i(x, y)
			if c == jugador or c == enemigo:
				continue
			if x < 3 or y < 3 or x >= cols - 3 or y >= filas - 3:
				continue
			if not dist_jugador.has(c):
				continue
			var dj: int = dist_jugador[c]
			if dj < SALIDA_DIST_MIN:
				continue
			var de: int = dist_enemigo.get(c, 999)
			var vecinos_libres: int = 0
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var n: Vector2i = c + d
				if n.y >= 0 and n.y < filas and n.x >= 0 and n.x < cols and matriz[n.y][n.x] == 0:
					vecinos_libres += 1

			var score: int = dj * 2 + (10 if vecinos_libres == 2 else 0) \
				- (20 if de < dj - 5 else 0)
			if ocultas:
				# En Plaza/Metro la salida debe quedar en un callejón sin salida.
				score += 90 if vecinos_libres == 1 else 0
			candidatos.append({"celda": c, "score": score})

	if candidatos.is_empty():
		return salida

	candidatos.sort_custom(func(a, b): return a["score"] > b["score"])
	return candidatos[0]["celda"]


func _dijkstra_distancias(origen: Vector2i) -> Dictionary:
	# El costo de cada paso es 1: un BFS calcula exactamente las mismas distancias
	# que Dijkstra, pero sin ordenar la cola en cada extracción.
	var dist: Dictionary = {origen: 0}
	var cola: Array[Vector2i] = [origen]
	var cabeza: int = 0
	var filas: int = matriz.size()
	var cols: int = matriz[0].size()
	while cabeza < cola.size():
		var c: Vector2i = cola[cabeza]
		cabeza += 1
		var d: int = dist[c]
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n: Vector2i = c + dir
			if n.y < 0 or n.y >= filas or n.x < 0 or n.x >= cols:
				continue
			if matriz[n.y][n.x] != 0 or dist.has(n):
				continue
			dist[n] = d + 1
			cola.append(n)
	return dist


# ── Victoria ─────────────────────────────────────────────────────────────────
func _on_jugador_llego_a_salida() -> void:
	print("¡Jugador escapó!")
	if enemigo_nodo != null and enemigo_nodo.has_method("congelar"):
		enemigo_nodo.congelar(true)
	if hud != null:
		hud._mostrar_victoria()
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file(Partida.ESCENA_MENU)


# ── Construcción y Geometría 3D ──────────────────────────────────────────────
func celda_a_mundo(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * tam_celda, 0.0, (c.y + 0.5) * tam_celda)


func _hay_salida() -> bool:
	return modo != Partida.Modo.SUPERVIVENCIA


func es_dijkstra() -> bool:
	return modo == Partida.Modo.DIJKSTRA


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


func _es_mapa_pasillos() -> bool:
	return archivo_mapa.to_lower().contains("pasillo")


func _es_mapa_cementerio() -> bool:
	return archivo_mapa.to_lower().contains("cementerio")


func _es_mapa_plaza() -> bool:
	return archivo_mapa.to_lower().contains("plaza")


func _es_mapa_metro() -> bool:
	return archivo_mapa.to_lower().contains("metro")


func _tipo_mapa() -> String:
	if _es_mapa_pasillos():
		return "pasillos"
	if _es_mapa_cementerio():
		return "cementerio"
	if _es_mapa_plaza():
		return "plaza"
	if _es_mapa_metro():
		return "metro"
	return "generico"


func _carpeta_texturas() -> String:
	var base: String = archivo_mapa.get_file().get_basename()
	var guion: int = base.find("_")
	if guion >= 0:
		base = base.substr(guion + 1)
	return "res://Assets/MapAssets/%s/" % base.capitalize()


func _cargar_textura(ruta: String) -> Texture2D:
	if ResourceLoader.exists(ruta):
		return load(ruta) as Texture2D
	return null


func _material_texturizado(nombre: String, color: Color, rugosidad: float,
		escala_metros: float = -1.0, es_cielo: bool = false) -> StandardMaterial3D:
	var carpeta: String = _carpeta_texturas()
	var albedo: Texture2D = _cargar_textura(carpeta + nombre + "_albedo.png")
	if not usar_texturas or albedo == null:
		var plano := _material(color, rugosidad)
		if es_cielo:
			_ajustar_material_cielo(plano)
		return plano

	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.albedo_color = Color.WHITE
	m.roughness = rugosidad
	if usar_normales:
		var normal: Texture2D = _cargar_textura(carpeta + nombre + "_normal.png")
		if normal != null:
			m.normal_enabled = true
			m.normal_texture = normal
			m.normal_scale = 0.8
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	var metros: float = metros_por_textura if escala_metros <= 0.0 else escala_metros
	var escala: float = 1.0 / maxf(0.05, metros)
	m.uv1_scale = Vector3(escala, escala, escala)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if es_cielo:
		_ajustar_material_cielo(m)
	return m


func _ajustar_material_cielo(m: StandardMaterial3D) -> void:
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	m.disable_receive_shadows = true


func _preparar_materiales() -> void:
	if solo_escenografia:
		_mat_suelo = _material_texturizado("suelo", Color(0.12, 0.14, 0.13), 0.95)
		_mat_techo = _material(Color(0.02, 0.03, 0.06))
		return

	var col_pared := Color(0.55, 0.55, 0.60)
	var col_suelo := Color(0.12, 0.12, 0.14)
	var col_techo := Color(0.08, 0.08, 0.09)
	match _tipo_mapa():
		"cementerio":
			col_pared = Color(0.36, 0.34, 0.32)
			col_suelo = Color(0.12, 0.14, 0.13)
			col_techo = Color(0.02, 0.03, 0.06)
		"plaza":
			col_pared = Color(0.55, 0.46, 0.33)
			col_suelo = Color(0.48, 0.44, 0.37)
			col_techo = Color(0.03, 0.04, 0.08)
		"metro":
			col_pared = Color(0.55, 0.58, 0.60)
			col_suelo = Color(0.29, 0.29, 0.30)
			col_techo = Color(0.24, 0.25, 0.26)
		"pasillos":
			col_pared = Color(0.20, 0.24, 0.20)
			col_suelo = Color(0.12, 0.09, 0.07)
			col_techo = Color(0.50, 0.48, 0.42)

	_mat_pared = _material_texturizado("pared", col_pared, 0.85)
	_mat_suelo = _material_texturizado("suelo", col_suelo, 0.95)
	_mat_techo = _material_texturizado("techo", col_techo, 1.0,
		metros_por_textura_cielo if es_exterior else -1.0, es_exterior)
	_mat_lapida = _material_texturizado("lapida", Color(0.45, 0.45, 0.45), 0.85)

	_mat_apt = {
		"zocalo": _material(Color(0.16, 0.11, 0.08)),
		"lambrin": _material(Color(0.20, 0.26, 0.23)),
		"moldura": _material(Color(0.14, 0.09, 0.06)),
		"papel": _material(Color(0.60, 0.56, 0.48)),
		"cornisa": _material(Color(0.18, 0.13, 0.09)),
		"marco": _material(Color(0.13, 0.09, 0.06)),
		"hoja": _material(Color(0.26, 0.14, 0.08)),
		"panel": _material(Color(0.19, 0.10, 0.06)),
		"laton": _material(Color(0.85, 0.72, 0.25), 0.25, 0.9),
		"alfombra": _material(Color(0.32, 0.07, 0.09)),
		"borde": _material(Color(0.40, 0.32, 0.15)),
		"foco": _material(Color(1.0, 0.90, 0.65)),
	}

	_mat_nichos.clear()
	for c in [
		Color(0.32, 0.65, 0.56), Color(0.85, 0.38, 0.52), Color(0.86, 0.54, 0.35),
		Color(0.88, 0.76, 0.40), Color(0.35, 0.55, 0.72), Color(0.92, 0.90, 0.86),
		Color(0.55, 0.72, 0.55),
	]:
		_mat_nichos.append(_material(c))
	_mat_nicho_marco = _material(Color(0.25, 0.24, 0.22))
	_mat_nicho_cruz = _material(Color(0.18, 0.16, 0.15))
	_mat_nicho_repisa = _material(Color(0.20, 0.20, 0.20))
	_mat_nicho_tejadillo = _material(Color(0.88, 0.88, 0.85))


func _construir_muros() -> void:
	if solo_escenografia:
		_construir_muros_simple()
		return
	match _tipo_mapa():
		"pasillos":
			_construir_muros_apartamentos()
		"cementerio":
			_construir_muros_cementerio()
		_:
			_construir_muros_texturizados()


func _construir_muros_cementerio() -> void:
	var cols: int = matriz[0].size()
	for y in matriz.size():
		var x: int = 0
		while x < cols:
			var tipo_muro: int = matriz[y][x]
			if tipo_muro == 0:
				x += 1
				continue

			if _es_visible(x, y):
				var inicio: int = x
				while x < cols and matriz[y][x] == tipo_muro and _es_visible(x, y):
					x += 1
				var largo: int = x - inicio
				var pos_centro := Vector3((inicio + largo / 2.0) * tam_celda, 0.0, (y + 0.5) * tam_celda)

				if tipo_muro == 1:
					_construir_muro_nichos_3_niveles(pos_centro, largo)
				elif tipo_muro == 2:
					_construir_mausoleo_antiguo(pos_centro, largo)
				elif tipo_muro == 3:
					_construir_tumba_baja(pos_centro, largo)
				elif tipo_muro == 4:
					_construir_fachada_entrada(pos_centro, largo)
				elif tipo_muro == 5:
					_construir_tumba_yacente(pos_centro, largo)
				elif tipo_muro == 6:
					_construir_mausoleo_piramide(pos_centro, largo)
			else:
				x += 1

	_construir_portal_arco_cementerio()


func _es_celda_fuente(x: int, y: int) -> bool:
	return fuente.x == x and fuente.y == y


func _es_celda_tren(x: int, y: int) -> bool:
	if tren_largo <= 0 or tren_inicio.x < 0:
		return false
	if tren_orientacion.to_lower() == "v":
		return x >= tren_inicio.x and x <= tren_inicio.x + 1 \
			and y >= tren_inicio.y and y < tren_inicio.y + tren_largo
	return y >= tren_inicio.y and y <= tren_inicio.y + 1 \
		and x >= tren_inicio.x and x < tren_inicio.x + tren_largo


func _construir_muros_texturizados() -> void:
	var cols: int = matriz[0].size()
	for y in matriz.size():
		var x: int = 0
		while x < cols:
			if matriz[y][x] == 0 or not _es_visible(x, y) \
					or _es_celda_fuente(x, y) or _es_celda_tren(x, y):
				x += 1
				continue
			var inicio: int = x
			while x < cols and matriz[y][x] != 0 and _es_visible(x, y) \
					and not _es_celda_fuente(x, y) and not _es_celda_tren(x, y):
				x += 1
			var largo: int = x - inicio
			var pos: Vector3 = Vector3((inicio + largo / 2.0) * tam_celda, alto_muro / 2.0, (y + 0.5) * tam_celda)
			var tam: Vector3 = Vector3(largo * tam_celda, alto_muro, tam_celda)
			_lote_caja(pos, tam, _mat_pared)
			_colision_caja(pos, tam)


func _lote_caja(pos: Vector3, tam: Vector3, mat: Material, rot_y: float = 0.0) -> void:
	_lote_caja_local(Transform3D(Basis(Vector3.UP, rot_y), pos), Vector3.ZERO, tam, mat)


func _lote_caja_local(base: Transform3D, pos_local: Vector3, tam: Vector3, mat: Material) -> void:
	var id: int = mat.get_instance_id()
	if not _lotes.has(id):
		_lotes[id] = {"mat": mat, "xforms": []}
	var xform := Transform3D(base.basis * Basis.from_scale(tam), base * pos_local)
	(_lotes[id]["xforms"] as Array).append(xform)


func _colision_caja(pos: Vector3, tam: Vector3) -> void:
	if _cuerpo_muros == null:
		_cuerpo_muros = StaticBody3D.new()
		_cuerpo_muros.name = "Muros_Colision"
		add_child(_cuerpo_muros)
	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = tam
	col.shape = forma
	col.position = pos
	_cuerpo_muros.add_child(col)


func _volcar_lotes() -> void:
	if _lotes.is_empty():
		return
	var ancho: float = matriz[0].size() * tam_celda
	var largo: float = matriz.size() * tam_celda
	var caja := AABB(
		Vector3(-tam_celda, -2.0, -tam_celda),
		Vector3(ancho + tam_celda * 2.0, maxf(altura_cielo, alto_muro) + 10.0, largo + tam_celda * 2.0)
	)
	var cubo := BoxMesh.new()
	cubo.size = Vector3.ONE
	for entrada in _lotes.values():
		var xforms: Array = entrada["xforms"]
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cubo
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = entrada["mat"]
		mmi.custom_aabb = caja
		add_child(mmi)
	_lotes.clear()


func _construir_muros_simple() -> void:
	var cols: int = matriz[0].size()
	var materiales: Dictionary = {
		1: _material(Color(0.36, 0.34, 0.32)),
		2: _material(Color(0.35, 0.33, 0.30)),
		3: _material(Color(0.22, 0.24, 0.26)),
		4: _material(Color(0.88, 0.65, 0.18)),
		5: _material(Color(0.85, 0.83, 0.80)),
		6: _material(Color(0.70, 0.55, 0.46)),
	}
	for y in matriz.size():
		var x: int = 0
		while x < cols:
			var tipo_muro: int = matriz[y][x]
			if tipo_muro == 0 or not _es_visible(x, y) \
					or _es_celda_fuente(x, y) or _es_celda_tren(x, y):
				x += 1
				continue
			var inicio: int = x
			while x < cols and matriz[y][x] == tipo_muro and _es_visible(x, y) \
					and not _es_celda_fuente(x, y) and not _es_celda_tren(x, y):
				x += 1
			var largo: int = x - inicio
			var altura: float = alto_muro
			if tipo_muro == 2 or tipo_muro == 4:
				altura = alto_muro * 1.15
			elif tipo_muro == 3:
				altura = 0.8
			elif tipo_muro == 5:
				altura = 1.6
			elif tipo_muro == 6:
				altura = 6.2
			var pos_centro := Vector3(
				(inicio + largo / 2.0) * tam_celda,
				altura / 2.0,
				(y + 0.5) * tam_celda
			)
			_crear_bloque(
				pos_centro,
				Vector3(largo * tam_celda, altura, tam_celda),
				materiales.get(tipo_muro, materiales[1]),
				false
			)


# ── Pasillos estilo Departamentos ───────────────────────────────────────────
func _construir_muros_apartamentos() -> void:
	var cols: int = matriz[0].size()
	var filas: int = matriz.size()

	# 1. Muros con capas de color, zócalos y molduras
	for y in filas:
		var x: int = 0
		while x < cols:
			var tipo_muro: int = matriz[y][x]
			if tipo_muro == 0:
				x += 1
				continue

			if _es_visible(x, y):
				var inicio: int = x
				while x < cols and matriz[y][x] == tipo_muro and _es_visible(x, y):
					x += 1
				var largo: int = x - inicio
				var pos_centro := Vector3((inicio + largo / 2.0) * tam_celda, 0.0, (y + 0.5) * tam_celda)
				_construir_bloque_departamento(pos_centro, largo)
			else:
				x += 1

	# 2. Puertas de departamentos a lo largo de los pasillos
	_colocar_puertas_departamentos()


func _construir_bloque_departamento(pos: Vector3, largo: int) -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.position = pos

	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(largo * tam_celda, alto_muro, tam_celda)
	col.shape = forma
	col.position = Vector3(0.0, alto_muro / 2.0, 0.0)
	cuerpo.add_child(col)

	var ancho: float = largo * tam_celda
	_lote_caja_local(Transform3D(Basis(), pos), Vector3(0.0, 0.125, 0.0),
		Vector3(ancho, 0.25, tam_celda + 0.04), _mat_apt["zocalo"])
	_lote_caja_local(Transform3D(Basis(), pos), Vector3(0.0, 0.725, 0.0),
		Vector3(ancho, 0.95, tam_celda + 0.02), _mat_apt["lambrin"])
	_lote_caja_local(Transform3D(Basis(), pos), Vector3(0.0, 1.24, 0.0),
		Vector3(ancho, 0.08, tam_celda + 0.05), _mat_apt["moldura"])
	var alto_sup: float = alto_muro - 1.43
	_lote_caja_local(Transform3D(Basis(), pos), Vector3(0.0, 1.28 + alto_sup / 2.0, 0.0),
		Vector3(ancho, alto_sup, tam_celda), _mat_apt["papel"])
	_lote_caja_local(Transform3D(Basis(), pos), Vector3(0.0, alto_muro - 0.075, 0.0),
		Vector3(ancho, 0.15, tam_celda + 0.04), _mat_apt["cornisa"])

	add_child(cuerpo)


func _colocar_puertas_departamentos() -> void:
	var filas: int = matriz.size()
	var cols: int = matriz[0].size()
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

	for y in filas:
		for x in cols:
			if matriz[y][x] == 0:
				continue
			if (x * 7 + y * 13) % 3 != 0:
				continue

			var centro_celda := celda_a_mundo(Vector2i(x, y))

			for d in dirs:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and nx < cols and ny >= 0 and ny < filas and matriz[ny][nx] == 0:
					var pos_puerta := centro_celda + Vector3(d.x * (tam_celda * 0.49), 0.0, d.y * (tam_celda * 0.49))
					var rot_y: float = 0.0
					if d == Vector2i(0, 1): rot_y = PI
					elif d == Vector2i(-1, 0): rot_y = PI / 2.0
					elif d == Vector2i(1, 0): rot_y = -PI / 2.0

					var base := Transform3D(Basis(Vector3.UP, rot_y), pos_puerta)
					_lote_caja_local(base, Vector3(0.0, 1.075, 0.0), Vector3(1.10, 2.15, 0.08), _mat_apt["marco"])
					_lote_caja_local(base, Vector3(0.0, 1.025, 0.02), Vector3(0.92, 2.05, 0.04), _mat_apt["hoja"])
					_lote_caja_local(base, Vector3(0.0, 0.50, 0.04), Vector3(0.68, 0.65, 0.02), _mat_apt["panel"])
					_lote_caja_local(base, Vector3(0.0, 1.40, 0.04), Vector3(0.68, 0.75, 0.02), _mat_apt["panel"])
					_lote_caja_local(base, Vector3(0.34, 0.98, 0.05), Vector3(0.07, 0.05, 0.06), _mat_apt["laton"])
					_lote_caja_local(base, Vector3(0.0, 1.68, 0.04), Vector3(0.24, 0.10, 0.02), _mat_apt["laton"])

					var puerta_nodo := Node3D.new()
					puerta_nodo.transform = base
					add_child(puerta_nodo)

					var lbl := Label3D.new()
					var num_depto: int = 101 + ((x * 5 + y * 7) % 89)
					lbl.text = str(num_depto)
					lbl.font_size = 32
					lbl.pixel_size = 0.003
					lbl.modulate = Color(0.12, 0.08, 0.04)
					lbl.position = Vector3(0.0, 1.68, 0.055)
					puerta_nodo.add_child(lbl)

					if (x + y) % 12 == 0:
						_lote_caja_local(base, Vector3(0.0, 2.35, 0.10), Vector3(0.14, 0.12, 0.12), _mat_apt["foco"])
						var luz := OmniLight3D.new()
						luz.position = Vector3(0.0, 2.30, 0.20)
						luz.light_color = Color(1.0, 0.85, 0.65)
						luz.light_energy = 0.6
						luz.omni_range = 3.5
						puerta_nodo.add_child(luz)

					break


func _crear_submalla(tam: Vector3, pos_local: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = tam
	m.mesh = caja
	m.material_override = mat
	m.position = pos_local
	return m


# ── Estructuras visuales del Cementerio ──────────────────────────────────────

# 1. Muro de nichos en 3 niveles de colores (Foto 3)
func _construir_muro_nichos_3_niveles(pos: Vector3, largo: int) -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.position = pos

	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(largo * tam_celda, alto_muro, tam_celda)
	col.shape = forma
	col.position = Vector3(0.0, alto_muro / 2.0, 0.0)
	cuerpo.add_child(col)

	var base := Transform3D(Basis(), pos)
	_lote_caja_local(base, Vector3(0.0, alto_muro / 2.0, 0.0),
		Vector3(largo * tam_celda, alto_muro, tam_celda), _mat_pared)
	_lote_caja_local(base, Vector3(0.0, alto_muro + 0.125, 0.0),
		Vector3(largo * tam_celda + 0.2, 0.25, tam_celda + 0.25), _mat_nicho_tejadillo)

	var alturas_pisos: Array[float] = [0.55, 1.50, 2.45]
	for i in largo:
		var x_local: float = (i - largo / 2.0 + 0.5) * tam_celda
		for sub_i in [-0.48, 0.48]:
			var x_nicho: float = x_local + sub_i * (tam_celda * 0.45)
			for piso in range(3):
				var y_nicho: float = alturas_pisos[piso]
				var idx_color: int = abs(int(x_nicho * 7.0 + y_nicho * 13.0 + i * 3.0)) % _mat_nichos.size()
				var mat_nicho: StandardMaterial3D = _mat_nichos[idx_color]

				for z_lado in [-1.0, 1.0]:
					var z_pos: float = z_lado * (tam_celda / 2.0 + 0.02)
					_lote_caja_local(base, Vector3(x_nicho, y_nicho, z_pos),
						Vector3(0.78, 0.78, 0.04), mat_nicho)
					_lote_caja_local(base, Vector3(x_nicho, y_nicho, z_pos - z_lado * 0.01),
						Vector3(0.88, 0.88, 0.02), _mat_nicho_marco)
					_lote_caja_local(base, Vector3(x_nicho, y_nicho + 0.05, z_pos + z_lado * 0.025),
						Vector3(0.08, 0.35, 0.03), _mat_nicho_cruz)
					_lote_caja_local(base, Vector3(x_nicho, y_nicho + 0.10, z_pos + z_lado * 0.025),
						Vector3(0.25, 0.08, 0.03), _mat_nicho_cruz)
					_lote_caja_local(base, Vector3(x_nicho, y_nicho - 0.36, z_pos + z_lado * 0.05),
						Vector3(0.50, 0.06, 0.12), _mat_nicho_repisa)

	add_child(cuerpo)


# 4. Fachada perimetral colonial amarilla con pilastras blancas y ventanas (Foto 1 y 5)
func _construir_fachada_entrada(pos: Vector3, largo: int) -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.position = pos
	var alt_fachada: float = alto_muro * 1.15

	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(largo * tam_celda, alt_fachada, tam_celda)
	col.shape = forma
	col.position = Vector3(0.0, alt_fachada / 2.0, 0.0)
	cuerpo.add_child(col)

	var mat_amarillo := _material(Color(0.88, 0.65, 0.18))
	var mat_blanco := _material(Color(0.94, 0.94, 0.92))
	var mat_ventana_marco := _material(Color(0.72, 0.68, 0.60))
	var mat_ventana_hueco := _material(Color(0.06, 0.06, 0.07))
	var mat_reja := _material(Color(0.12, 0.12, 0.12), 0.3, 0.8)

	# Muro principal amarillo
	cuerpo.add_child(_crear_submalla(
		Vector3(largo * tam_celda, alt_fachada, tam_celda),
		Vector3(0.0, alt_fachada / 2.0, 0.0),
		mat_amarillo
	))
	# Zócalo inferior blanco
	cuerpo.add_child(_crear_submalla(
		Vector3(largo * tam_celda + 0.05, 0.40, tam_celda + 0.08),
		Vector3(0.0, 0.20, 0.0),
		mat_blanco
	))
	# Cornisa superior corrida blanca
	cuerpo.add_child(_crear_submalla(
		Vector3(largo * tam_celda + 0.10, 0.35, tam_celda + 0.15),
		Vector3(0.0, alt_fachada + 0.10, 0.0),
		mat_blanco
	))

	# Pilastras blancas y ventanas ojivales con rejas
	for i in largo:
		var x_local: float = (i - largo / 2.0 + 0.5) * tam_celda
		# Pilastra blanca vertical
		cuerpo.add_child(_crear_submalla(
			Vector3(0.35, alt_fachada - 0.40, tam_celda + 0.10),
			Vector3(x_local, 0.40 + (alt_fachada - 0.40) / 2.0, 0.0),
			mat_blanco
		))
		# Ventana ojival en ambas caras (exterior e interior)
		for z_lado in [-1.0, 1.0]:
			var z_offset: float = z_lado * (tam_celda / 2.0 + 0.02)
			cuerpo.add_child(_crear_submalla(
				Vector3(0.75, 1.35, 0.06),
				Vector3(x_local + 0.25, 1.6, z_offset),
				mat_ventana_marco
			))
			cuerpo.add_child(_crear_submalla(
				Vector3(0.55, 1.15, 0.08),
				Vector3(x_local + 0.25, 1.6, z_offset),
				mat_ventana_hueco
			))
			cuerpo.add_child(_crear_submalla(
				Vector3(0.50, 1.10, 0.10),
				Vector3(x_local + 0.25, 1.6, z_offset),
				mat_reja
			))

	add_child(cuerpo)


# Portal de arco de cantera con tímpano ornamental y verja sobre el vano de entrada (Foto 1 y 5)
func _construir_portal_arco_cementerio() -> void:
	var x_inicio: float = 16.0 * tam_celda
	var x_fin: float = 22.0 * tam_celda
	var x_centro: float = (x_inicio + x_fin) / 2.0
	var z_centro: float = 40.5 * tam_celda
	var ancho_portal: float = x_fin - x_inicio
	var mat_cantera := _material(Color(0.58, 0.52, 0.44))
	var mat_reja := _material(Color(0.12, 0.12, 0.12), 0.3, 0.8)

	var portal := Node3D.new()
	portal.position = Vector3(x_centro, 0.0, z_centro)
	add_child(portal)

	# Pilastras monumentales de cantera a los lados del vano
	portal.add_child(_crear_submalla(
		Vector3(1.2, 5.0, tam_celda * 1.4),
		Vector3(-ancho_portal / 2.0 + 0.6, 2.5, 0.0),
		mat_cantera
	))
	portal.add_child(_crear_submalla(
		Vector3(1.2, 5.0, tam_celda * 1.4),
		Vector3(ancho_portal / 2.0 - 0.6, 2.5, 0.0),
		mat_cantera
	))
	# Viga / Arquitrabe de arco superior (a 3.6m para paso despejado del jugador)
	portal.add_child(_crear_submalla(
		Vector3(ancho_portal + 0.8, 0.8, tam_celda * 1.2),
		Vector3(0.0, 4.0, 0.0),
		mat_cantera
	))
	# Tímpano / Frontón semicircular ornamental con relieve (Foto 1)
	portal.add_child(_crear_submalla(
		Vector3(ancho_portal * 0.75, 1.2, tam_celda * 0.8),
		Vector3(0.0, 4.9, 0.0),
		mat_cantera
	))
	portal.add_child(_crear_submalla(
		Vector3(1.6, 0.8, tam_celda * 0.9),
		Vector3(0.0, 4.9, 0.0),
		_material(Color(0.68, 0.62, 0.52))
	))
	# Verjas de hierro forjado a los lados
	for x_lado in [-1.0, 1.0]:
		portal.add_child(_crear_submalla(
			Vector3(1.4, 3.2, 0.1),
			Vector3(x_lado * (ancho_portal / 2.0 - 1.4), 1.6, 0.0),
			mat_reja
		))


# 5. Tumba especial de la estatua yacente de mármol con rosas y velas (Foto 2)
func _construir_tumba_yacente(pos: Vector3, largo: int) -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.position = pos

	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(largo * tam_celda, 1.6, tam_celda)
	col.shape = forma
	col.position = Vector3(0.0, 0.8, 0.0)
	cuerpo.add_child(col)

	var mat_marmol_base := _material(Color(0.85, 0.83, 0.80), 0.7, 0.1)
	var mat_marmol_estatua := _material(Color(0.92, 0.90, 0.86), 0.4, 0.05)
	var mat_flores := _material(Color(0.65, 0.12, 0.15))
	var mat_cera := _material(Color(0.96, 0.93, 0.75))

	var ancho_tumba: float = minf(largo * tam_celda * 0.85, 4.0)
	var prof_tumba: float = tam_celda * 0.85

	# Base y sarcófago
	cuerpo.add_child(_crear_submalla(
		Vector3(ancho_tumba + 0.3, 0.35, prof_tumba + 0.3),
		Vector3(0.0, 0.175, 0.0),
		mat_marmol_base
	))
	cuerpo.add_child(_crear_submalla(
		Vector3(ancho_tumba, 0.75, prof_tumba),
		Vector3(0.0, 0.725, 0.0),
		mat_marmol_base
	))
	cuerpo.add_child(_crear_submalla(
		Vector3(ancho_tumba + 0.2, 0.15, prof_tumba + 0.2),
		Vector3(0.0, 1.15, 0.0),
		mat_marmol_base
	))

	# Estatua Yacente (Foto 2)
	# Almohada de mármol
	cuerpo.add_child(_crear_submalla(
		Vector3(0.65, 0.25, 0.75),
		Vector3(-ancho_tumba * 0.32, 1.30, 0.0),
		mat_marmol_estatua
	))
	# Cabeza
	cuerpo.add_child(_crear_submalla(
		Vector3(0.40, 0.30, 0.38),
		Vector3(-ancho_tumba * 0.30, 1.45, 0.0),
		mat_marmol_estatua
	))
	# Torso y brazos con libro/rosario
	cuerpo.add_child(_crear_submalla(
		Vector3(0.85, 0.32, 0.60),
		Vector3(-ancho_tumba * 0.05, 1.35, 0.0),
		mat_marmol_estatua
	))
	# Manto y piernas
	cuerpo.add_child(_crear_submalla(
		Vector3(1.35, 0.26, 0.55),
		Vector3(ancho_tumba * 0.25, 1.30, 0.0),
		mat_marmol_estatua
	))
	# Pies
	cuerpo.add_child(_crear_submalla(
		Vector3(0.25, 0.30, 0.35),
		Vector3(ancho_tumba * 0.44, 1.30, 0.0),
		mat_marmol_estatua
	))
	# Rosas marchitas sobre la losa
	cuerpo.add_child(_crear_submalla(
		Vector3(0.25, 0.08, 0.25),
		Vector3(-ancho_tumba * 0.05, 1.52, 0.18),
		mat_flores
	))

	# Velas votivas con luz cálida
	for v in [Vector3(ancho_tumba * 0.46, 1.25, -prof_tumba * 0.35), Vector3(ancho_tumba * 0.46, 1.25, prof_tumba * 0.35)]:
		cuerpo.add_child(_crear_submalla(Vector3(0.08, 0.25, 0.08), v, mat_cera))
		var luz_vela := OmniLight3D.new()
		luz_vela.position = v + Vector3(0.0, 0.20, 0.0)
		luz_vela.light_color = Color(1.0, 0.72, 0.35)
		luz_vela.light_energy = 0.5
		luz_vela.omni_range = 2.5
		cuerpo.add_child(luz_vela)

	add_child(cuerpo)


# 6. Mausoleo piramidal monumental estilo egipcio con estatua y esfinge (Foto 4)
func _construir_mausoleo_piramide(pos: Vector3, largo: int) -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.position = pos
	var alt_piramide: float = 6.2

	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(largo * tam_celda, alt_piramide, tam_celda * 2.0)
	col.shape = forma
	col.position = Vector3(0.0, alt_piramide / 2.0, 0.0)
	cuerpo.add_child(col)

	var mat_granito := _material(Color(0.70, 0.55, 0.46), 0.85, 0.05)
	var mat_base := _material(Color(0.55, 0.50, 0.45), 0.8, 0.05)
	var mat_puerta := _material(Color(0.08, 0.08, 0.08))
	var mat_estatua := _material(Color(0.90, 0.88, 0.84), 0.5, 0.05)
	var mat_esfinge := _material(Color(0.85, 0.78, 0.68), 0.6, 0.05)

	var base_w: float = largo * tam_celda
	var base_d: float = tam_celda * 1.8

	# Plataforma escalonada base
	cuerpo.add_child(_crear_submalla(
		Vector3(base_w, 0.6, base_d),
		Vector3(0.0, 0.3, 0.0),
		mat_base
	))

	# Pirámide en 4 gradas hacia la cúspide
	var capas: Array = [
		{"h": 1.4, "w": base_w * 0.90, "d": base_d * 0.90, "y": 1.3},
		{"h": 1.4, "w": base_w * 0.68, "d": base_d * 0.68, "y": 2.7},
		{"h": 1.4, "w": base_w * 0.44, "d": base_d * 0.44, "y": 4.1},
		{"h": 1.4, "w": base_w * 0.20, "d": base_d * 0.20, "y": 5.5},
	]
	for c in capas:
		cuerpo.add_child(_crear_submalla(Vector3(c["w"], c["h"], c["d"]), Vector3(0.0, c["y"], 0.0), mat_granito))

	# Cúspide
	cuerpo.add_child(_crear_submalla(Vector3(base_w * 0.08, 0.6, base_d * 0.08), Vector3(0.0, 6.2, 0.0), mat_granito))

	# Portal egipcio frontal (Foto 4)
	var z_portal: float = base_d * 0.48
	# Jambas y arquitrabe
	cuerpo.add_child(_crear_submalla(Vector3(2.6, 3.2, 0.6), Vector3(0.0, 1.9, z_portal), mat_base))
	# Cornisa de cavetto
	cuerpo.add_child(_crear_submalla(Vector3(3.0, 0.45, 0.8), Vector3(0.0, 3.4, z_portal), mat_base))
	# Puerta oscura con cruz
	cuerpo.add_child(_crear_submalla(Vector3(1.4, 2.4, 0.2), Vector3(0.0, 1.5, z_portal + 0.25), mat_puerta))
	cuerpo.add_child(_crear_submalla(Vector3(0.12, 1.2, 0.08), Vector3(0.0, 1.6, z_portal + 0.36), _material(Color(0.85, 0.85, 0.85))))
	cuerpo.add_child(_crear_submalla(Vector3(0.80, 0.12, 0.08), Vector3(0.0, 1.7, z_portal + 0.36), _material(Color(0.85, 0.85, 0.85))))

	# Estatua Neoclásica a la izquierda del portal (Foto 4)
	var x_izq: float = -2.2
	cuerpo.add_child(_crear_submalla(Vector3(0.9, 1.1, 0.9), Vector3(x_izq, 1.15, z_portal), mat_base))
	cuerpo.add_child(_crear_submalla(Vector3(0.45, 1.5, 0.45), Vector3(x_izq, 2.45, z_portal), mat_estatua))
	cuerpo.add_child(_crear_submalla(Vector3(0.15, 0.65, 0.15), Vector3(x_izq - 0.25, 2.9, z_portal), mat_estatua))

	# Esfinge egipcia a la derecha del portal (Foto 4)
	var x_der: float = 2.4
	cuerpo.add_child(_crear_submalla(Vector3(1.6, 0.9, 1.0), Vector3(x_der, 1.05, z_portal), mat_base))
	cuerpo.add_child(_crear_submalla(Vector3(1.3, 0.55, 0.7), Vector3(x_der, 1.775, z_portal), mat_esfinge))
	cuerpo.add_child(_crear_submalla(Vector3(0.55, 0.85, 0.6), Vector3(x_der - 0.40, 2.2, z_portal), mat_esfinge))

	add_child(cuerpo)


# 2. Panteones y mausoleos antiguos
func _construir_mausoleo_antiguo(pos: Vector3, largo: int) -> void:
	var alt := alto_muro * 1.15
	var tam_base := Vector3(largo * tam_celda, alt, tam_celda)
	_crear_bloque(pos + Vector3(0, alt / 2.0, 0), tam_base, _mat_lapida, true)
	var tam_techo := Vector3(largo * tam_celda - 0.2, 0.6, tam_celda - 0.2)
	_crear_bloque(pos + Vector3(0, alt + 0.3, 0), tam_techo, _mat_nicho_marco, false)


# 3. Lápidas y monumentos tumbales bajos con cruz
func _construir_tumba_baja(pos: Vector3, largo: int) -> void:
	var alt_tumba := 0.8
	var tam_tumba := Vector3(largo * tam_celda * 0.85, alt_tumba, tam_celda * 0.75)
	_crear_bloque(pos + Vector3(0, alt_tumba / 2.0, 0), tam_tumba, _mat_lapida, true)
	var alt_cruz := 1.6
	var tam_cruz := Vector3(0.3, alt_cruz, 0.3)
	_crear_bloque(pos + Vector3(0, alt_cruz / 2.0, -tam_celda * 0.25), tam_cruz, _mat_nicho_cruz, false)


# Suelo y Techo
func _obtener_fuente_metro() -> Font:
	if _fuente_metro == null:
		_fuente_metro = load("res://Scenes/Assets/Fonts/NotoSansJP-Metro.ttf") as Font
	return _fuente_metro


func _crear_label_metro(texto: String, pos: Vector3, altura_texto: float,
		color: Color, rot_y: float = 0.0) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = texto
	lbl.font = _obtener_fuente_metro()
	lbl.font_size = 64
	lbl.pixel_size = altura_texto / 64.0
	lbl.modulate = color
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.75)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = pos
	lbl.rotation.y = rot_y
	return lbl


func _cartel_metro(pos: Vector3, rot_y: float, texto: String, color: Color, ancho: float = 5.2) -> void:
	var raiz := Node3D.new()
	raiz.position = pos
	raiz.rotation.y = rot_y
	add_child(raiz)
	var base := Transform3D(Basis(Vector3.UP, rot_y), pos)

	var alto: float = 1.2
	var mat_color := _material(color, 0.5, 0.2)
	_lote_caja_local(base, Vector3.ZERO, Vector3(ancho, alto, 0.14), _mat_metro_fondo)
	_lote_caja_local(base, Vector3(0.0, alto / 2.0 - 0.05, 0.0), Vector3(ancho, 0.10, 0.16), mat_color)
	_lote_caja_local(base, Vector3(0.0, -alto / 2.0 + 0.05, 0.0), Vector3(ancho, 0.10, 0.16), mat_color)
	_lote_caja_local(base, Vector3(-ancho / 2.0 + 0.55, 0.0, 0.0), Vector3(0.72, 0.72, 0.16), mat_color)

	raiz.add_child(_crear_label_metro(texto, Vector3(0.18, 0.0, 0.09), 0.36, Color(0.96, 0.97, 0.98)))
	raiz.add_child(_crear_label_metro(texto, Vector3(0.18, 0.0, -0.09), 0.36, Color(0.96, 0.97, 0.98), PI))

	var alto_tirante: float = maxf(0.35, alto_muro - pos.y - alto / 2.0)
	for x in [-ancho * 0.32, ancho * 0.32]:
		_lote_caja_local(base, Vector3(x, alto / 2.0 + alto_tirante / 2.0, 0.0),
			Vector3(0.06, alto_tirante, 0.06), _mat_metro_metal)


func _poster_metro(pos: Vector3, rot_y: float, titulo: String, subtitulo: String, color: Color) -> void:
	var raiz := Node3D.new()
	raiz.position = pos
	raiz.rotation.y = rot_y
	add_child(raiz)
	var base := Transform3D(Basis(Vector3.UP, rot_y), pos)

	var ancho: float = 2.5
	var alto: float = 3.4
	var mat_color := _material(color, 0.55, 0.15)
	_lote_caja_local(base, Vector3.ZERO, Vector3(ancho, alto, 0.12), _mat_metro_poster_fondo)
	_lote_caja_local(base, Vector3(0.0, alto / 2.0 - 0.11, 0.0), Vector3(ancho, 0.22, 0.14), mat_color)
	_lote_caja_local(base, Vector3(0.0, -0.15, 0.0), Vector3(ancho * 0.86, alto * 0.48, 0.13), _mat_metro_poster_panel)
	_lote_caja_local(base, Vector3(0.0, -alto / 2.0 + 0.1, 0.0), Vector3(ancho * 0.9, 0.1, 0.14), mat_color)
	raiz.add_child(_crear_label_metro(titulo, Vector3(0.0, 0.62, 0.09), 0.52, Color(0.98, 0.98, 0.96)))
	raiz.add_child(_crear_label_metro(subtitulo, Vector3(0.0, -1.02, 0.09), 0.28, Color(0.92, 0.94, 0.96)))


func _construir_detalles_metro() -> void:
	if tren_largo <= 0 or tren_inicio.x < 0:
		return
	var vertical: bool = tren_orientacion.to_lower() == "v"
	if vertical:
		return

	_mat_metro_fondo = _material(Color(0.04, 0.06, 0.08), 0.55, 0.25)
	_mat_metro_metal = _material(Color(0.15, 0.16, 0.18), 0.4, 0.8)
	_mat_metro_poster_fondo = _material(Color(0.07, 0.07, 0.09), 0.75, 0.1)
	_mat_metro_poster_panel = _material(Color(0.10, 0.10, 0.13), 0.8, 0.1)

	var centro_x: float = (tren_inicio.x + tren_largo / 2.0) * tam_celda
	var centro_z: float = (tren_inicio.y + 1.0) * tam_celda
	var largo_total: float = tren_largo * tam_celda
	var colores: Array[Color] = [
		Color(0.00, 0.62, 0.45), Color(0.90, 0.02, 0.15),
		Color(0.95, 0.55, 0.02), Color(0.00, 0.55, 0.80),
	]
	var textos: Array[String] = [
		"新宿 SHINJUKU  →", "←  渋谷 SHIBUYA",
		"東京 TOKYO  →", "←  池袋 IKEBUKURO",
	]

	var mat_tactil := _material(Color(0.95, 0.72, 0.08), 0.75)
	for lado in [-1.0, 1.0]:
		_lote_caja(
			Vector3(centro_x, 0.03, centro_z + lado * (tam_celda + 1.0)),
			Vector3(largo_total, 0.025, 0.42),
			mat_tactil
		)

	_cartel_metro(Vector3(centro_x, 3.9, 12.0), 0.0, "新橋 SHIMBASHI  /  NEO TOKYO", colores[0], 7.2)
	_cartel_metro(Vector3(centro_x, 3.9, (matriz.size() - 6) * tam_celda), 0.0,
		"←  出口 EXIT  /  南口 SOUTH", colores[2], 6.4)

	for i in 3:
		var x: float = centro_x + (i - 1) * 22.0
		_cartel_metro(Vector3(x, 3.9, centro_z), PI / 2.0, textos[i], colores[i])

	var anuncios: Array = [
		["ラーメン", "RAMEN 24H", Color(0.85, 0.08, 0.10)],
		["漫画", "MANGA", Color(0.05, 0.45, 0.85)],
		["喫茶", "CAFÉ", Color(0.15, 0.60, 0.35)],
		["売店", "KIOSK", Color(0.95, 0.55, 0.05)],
		["東京", "TOKYO", Color(0.55, 0.15, 0.65)],
		["案内", "INFORMATION", Color(0.05, 0.60, 0.65)],
		["未来", "FUTURE", Color(0.80, 0.20, 0.55)],
		["夜行", "NIGHT LINE", Color(0.20, 0.25, 0.75)],
	]
	var x_oeste: float = 26.1
	var x_este: float = 135.9
	for i in 2:
		var z: float = centro_z + (i * 2.0 - 1.0) * 18.0
		var a: Array = anuncios[i * 2]
		_poster_metro(Vector3(x_oeste, 1.72, z), PI / 2.0, a[0], a[1], a[2])
		var b: Array = anuncios[i * 2 + 1]
		_poster_metro(Vector3(x_este, 1.72, z), -PI / 2.0, b[0], b[1], b[2])
	var z_norte: float = 16.1
	var z_sur: float = 89.9
	for i in 2:
		var x: float = centro_x + (i * 2.0 - 1.0) * 21.0
		var a: Array = anuncios[4 + i]
		_poster_metro(Vector3(x, 1.72, z_norte), 0.0, a[0], a[1], a[2])
		var b: Array = anuncios[6 + i]
		_poster_metro(Vector3(x, 1.72, z_sur), PI, b[0], b[1], b[2])


func _construir_detalles_plaza() -> void:
	if fuente.x < 0 or fuente.y < 0:
		return
	var centro: Vector3 = celda_a_mundo(fuente)
	var mat_hierro := _material(Color(0.10, 0.11, 0.13), 0.45, 0.8)
	var mat_luz := _material(Color(1.0, 0.84, 0.55))
	mat_luz.emission_enabled = true
	mat_luz.emission = Color(1.0, 0.70, 0.35)
	mat_luz.emission_energy_multiplier = 1.4
	var mat_madera := _material(Color(0.22, 0.13, 0.07), 0.85)
	var mat_verde := _material(Color(0.08, 0.22, 0.10), 0.9)
	var mat_tronco := _material(Color(0.16, 0.10, 0.06), 0.95)

	for i in 8:
		var ang: float = TAU * i / 8.0
		var pos: Vector3 = centro + Vector3(cos(ang) * 7.5, 0.0, sin(ang) * 7.5)
		add_child(_malla_caja(Vector3(0.18, 4.4, 0.18), pos + Vector3(0.0, 2.2, 0.0), mat_hierro))
		add_child(_malla_caja(Vector3(0.52, 0.12, 0.52), pos + Vector3(0.0, 4.35, 0.0), mat_hierro))
		add_child(_malla_caja(Vector3(0.28, 0.38, 0.28), pos + Vector3(0.0, 4.10, 0.0), mat_luz))
		if i % 2 == 0:
			var luz := OmniLight3D.new()
			luz.position = pos + Vector3(0.0, 3.95, 0.0)
			luz.light_color = Color(1.0, 0.78, 0.45)
			luz.light_energy = 0.8
			luz.omni_range = 7.0
			add_child(luz)

	for i in 4:
		var ang: float = TAU * i / 4.0
		var pos: Vector3 = centro + Vector3(cos(ang) * 4.8, 0.0, sin(ang) * 4.8)
		var banco := Node3D.new()
		banco.position = pos
		banco.rotation.y = atan2(-cos(ang), -sin(ang))
		banco.add_child(_malla_caja(Vector3(2.2, 0.16, 0.65), Vector3(0.0, 0.48, 0.0), mat_madera))
		banco.add_child(_malla_caja(Vector3(2.2, 0.55, 0.10), Vector3(0.0, 0.78, -0.30), mat_madera))
		for x in [-0.85, 0.85]:
			banco.add_child(_malla_caja(Vector3(0.10, 0.48, 0.55), Vector3(x, 0.24, 0.0), mat_hierro))
		add_child(banco)

	for i in 4:
		var ang: float = TAU * i / 4.0 + PI / 4.0
		var pos: Vector3 = centro + Vector3(cos(ang) * 6.6, 0.0, sin(ang) * 6.6)
		add_child(_malla_cilindro(0.20, 0.30, 2.2, pos + Vector3(0.0, 1.1, 0.0), mat_tronco))
		var copa := MeshInstance3D.new()
		var esfera := SphereMesh.new()
		esfera.radius = 1.25
		esfera.height = 2.5
		copa.mesh = esfera
		copa.material_override = mat_verde
		copa.position = pos + Vector3(0.0, 2.9, 0.0)
		add_child(copa)


func _construir_fuente() -> void:
	if fuente.x < 0 or fuente.y < 0:
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Fuente_%d_%d" % [fuente.x, fuente.y]
	cuerpo.add_to_group("fuente")
	cuerpo.position = celda_a_mundo(fuente)

	var agua := _material(Color(0.04, 0.23, 0.30))
	agua.metallic = 0.25
	agua.roughness = 0.06
	agua.emission_enabled = true
	agua.emission = Color(0.02, 0.12, 0.16)
	agua.emission_energy_multiplier = 0.8
	var piedra := _material(Color(0.62, 0.58, 0.50), 0.9)
	var piedra_oscura := _material(Color(0.42, 0.40, 0.36), 0.95)

	var radio: float = 3.0
	cuerpo.add_child(_malla_cilindro(radio, radio * 1.08, 0.60, Vector3(0.0, 0.30, 0.0), piedra))
	cuerpo.add_child(_malla_cilindro(radio * 0.91, radio * 0.91, 0.08, Vector3(0.0, 0.62, 0.0), agua))
	cuerpo.add_child(_malla_cilindro(radio * 0.86, radio * 0.86, 0.10, Vector3(0.0, 0.71, 0.0), piedra_oscura))
	cuerpo.add_child(_malla_cilindro(0.72, 0.98, 1.50, Vector3(0.0, 1.42, 0.0), piedra))
	cuerpo.add_child(_malla_cilindro(1.62, 0.86, 0.36, Vector3(0.0, 2.22, 0.0), piedra))
	cuerpo.add_child(_malla_cilindro(1.44, 1.44, 0.06, Vector3(0.0, 2.41, 0.0), agua))
	cuerpo.add_child(_malla_cilindro(0.17, 0.25, 1.40, Vector3(0.0, 3.10, 0.0), piedra))
	cuerpo.add_child(_malla_cilindro(0.56, 0.30, 0.20, Vector3(0.0, 3.84, 0.0), piedra))

	var remate := MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = 0.28
	esfera.height = 0.56
	remate.mesh = esfera
	remate.material_override = piedra
	remate.position = Vector3(0.0, 4.10, 0.0)
	cuerpo.add_child(remate)

	var col := CollisionShape3D.new()
	var forma := CylinderShape3D.new()
	forma.radius = radio + 0.15
	forma.height = 0.70
	col.shape = forma
	col.position = Vector3(0.0, 0.35, 0.0)
	cuerpo.add_child(col)
	add_child(cuerpo)


func _construir_tren() -> void:
	if tren_largo <= 0 or tren_inicio.x < 0:
		return
	var vertical: bool = tren_orientacion.to_lower() == "v"
	var largo_total: float = tren_largo * tam_celda
	var ancho_total: float = 2.0 * tam_celda
	var centro_x: float = (tren_inicio.x + (1.0 if vertical else tren_largo / 2.0)) * tam_celda
	var centro_z: float = (tren_inicio.y + (tren_largo / 2.0 if vertical else 1.0)) * tam_celda
	var raiz := Node3D.new()
	raiz.name = "Tren_%d_%d" % [tren_inicio.x, tren_inicio.y]
	raiz.add_to_group("tren")
	raiz.position = Vector3(centro_x, 0.0, centro_z)
	if vertical:
		raiz.rotation.y = PI * 0.5
	add_child(raiz)
	var base := Transform3D(Basis(Vector3.UP, raiz.rotation.y), raiz.position)

	var balasto := _material(Color(0.12, 0.12, 0.13))
	balasto.roughness = 0.95
	_lote_caja_local(base, Vector3(0.0, 0.05, 0.0),
		Vector3(largo_total, 0.1, ancho_total * 0.9), balasto)

	var durmiente := _material(Color(0.18, 0.14, 0.11))
	durmiente.roughness = 0.9
	var x_durmiente: float = -largo_total * 0.5 + 1.0
	while x_durmiente < largo_total * 0.5:
		_lote_caja_local(base, Vector3(x_durmiente, 0.09, 0.0),
			Vector3(0.25, 0.08, ancho_total * 0.82), durmiente)
		x_durmiente += 2.0

	var metal := _material(Color(0.42, 0.44, 0.48))
	metal.metallic = 0.85
	metal.roughness = 0.28
	_lote_caja_local(base, Vector3(0.0, 0.17, -0.75), Vector3(largo_total, 0.12, 0.1), metal)
	_lote_caja_local(base, Vector3(0.0, 0.17, 0.75), Vector3(largo_total, 0.12, 0.1), metal)

	var carroceria := _material(Color(0.17, 0.22, 0.29))
	carroceria.metallic = 0.55
	carroceria.roughness = 0.38
	var techo := _material(Color(0.10, 0.12, 0.15))
	techo.metallic = 0.4
	techo.roughness = 0.55
	var ventanas := _material(Color(0.35, 0.55, 0.7))
	ventanas.emission_enabled = true
	ventanas.emission = Color(0.45, 0.72, 1.0)
	ventanas.emission_energy_multiplier = 1.6
	var franja := _material(Color(0.85, 0.68, 0.16))
	franja.metallic = 0.2
	franja.roughness = 0.5

	var num_coches: int = clampi(int(round(largo_total / 14.0)), 4, 8)
	var separacion: float = 0.9
	var largo_coche: float = (largo_total - separacion * (num_coches - 1)) / num_coches
	var ancho_cuerpo: float = ancho_total * 0.82
	var alto_cuerpo: float = 2.45
	var y_base: float = 0.25
	for i in num_coches:
		var x_coche: float = -largo_total * 0.5 + largo_coche * 0.5 + i * (largo_coche + separacion)
		_lote_caja_local(base, Vector3(x_coche, y_base + alto_cuerpo * 0.5, 0.0),
			Vector3(largo_coche, alto_cuerpo, ancho_cuerpo), carroceria)
		_lote_caja_local(base, Vector3(x_coche, y_base + alto_cuerpo + 0.09, 0.0),
			Vector3(largo_coche * 0.96, 0.18, ancho_cuerpo * 0.92), techo)
		for lado in [-1.0, 1.0]:
			var z_lado: float = lado * (ancho_cuerpo * 0.5 + 0.03)
			_lote_caja_local(base, Vector3(x_coche, y_base + alto_cuerpo * 0.66, z_lado),
				Vector3(largo_coche * 0.72, 0.65, 0.05), ventanas)
			_lote_caja_local(base, Vector3(x_coche, y_base + 0.34, z_lado),
				Vector3(largo_coche * 0.92, 0.12, 0.05), franja)

	var colision := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(largo_total, 2.8, ancho_total * 0.9)
	col.shape = caja
	col.position = Vector3(0.0, 1.4, 0.0)
	colision.add_child(col)
	raiz.add_child(colision)


func _malla_cilindro(radio_sup: float, radio_inf: float, alto: float, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	var malla := MeshInstance3D.new()
	var cilindro := CylinderMesh.new()
	cilindro.top_radius = radio_sup
	cilindro.bottom_radius = radio_inf
	cilindro.height = alto
	cilindro.radial_segments = 24
	malla.mesh = cilindro
	malla.material_override = mat
	malla.position = pos
	return malla


func _malla_caja(tam: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var malla := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = tam
	malla.mesh = caja
	malla.material_override = mat
	malla.position = pos
	return malla


func _construir_suelo_y_techo() -> void:
	var filas: int = matriz.size()
	var cols: int = matriz[0].size()
	var tam_mapa_x: float = cols * tam_celda
	var tam_mapa_z: float = filas * tam_celda

	_crear_bloque(
		Vector3(tam_mapa_x / 2.0, -0.1, tam_mapa_z / 2.0),
		Vector3(tam_mapa_x, 0.2, tam_mapa_z),
		_mat_suelo,
		true
	)
	if _es_mapa_pasillos():
		_construir_alfombra_pasillos()

	if con_techo:
		if es_exterior:
			_crear_bloque(
				Vector3(tam_mapa_x / 2.0, maxf(altura_cielo, alto_muro + 6.0), tam_mapa_z / 2.0),
				Vector3(tam_mapa_x * 4.0, 0.2, tam_mapa_z * 4.0),
				_mat_techo,
				false
			)
		else:
			_crear_bloque(
				Vector3(tam_mapa_x / 2.0, alto_muro + 0.1, tam_mapa_z / 2.0),
				Vector3(tam_mapa_x, 0.2, tam_mapa_z),
				_mat_techo,
				false
			)


func _construir_alfombra_pasillos() -> void:
	for y in matriz.size():
		for x in matriz[0].size():
			if matriz[y][x] == 0:
				var pos: Vector3 = celda_a_mundo(Vector2i(x, y))
				_lote_caja(pos + Vector3(0.0, 0.005, 0.0),
					Vector3(tam_celda * 0.78, 0.01, tam_celda * 0.78), _mat_apt["borde"])
				_lote_caja(pos + Vector3(0.0, 0.01, 0.0),
					Vector3(tam_celda * 0.70, 0.02, tam_celda * 0.70), _mat_apt["alfombra"])


func _crear_bloque(pos: Vector3, tam: Vector3, mat: Material, con_colision: bool) -> void:
	var malla := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = tam
	malla.mesh = caja
	malla.material_override = mat
	if not con_colision:
		malla.position = pos
		add_child(malla)
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.position = pos
	cuerpo.add_child(malla)
	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = tam
	col.shape = forma
	cuerpo.add_child(col)
	add_child(cuerpo)


func _material(color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
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
	jugador_nodo.celda_cambiada.connect(_on_celda_cambiada)
	jugador_nodo.celda_cambiada.connect(enemigo_nodo.registrar_movimiento_jugador)
	if es_dijkstra():
		_recalcular_ruta_jugador()
	hud = HUD.new()
	add_child(hud)
	hud.conectar(jugador_nodo, enemigo_nodo)


func _on_celda_cambiada(celda: Vector2i) -> void:
	if es_dijkstra():
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


func _on_perk_tomado(tipo: int) -> void:
	_perks_en_mapa.erase(tipo)
	posiciones_perks.erase(tipo)
	if _perks_en_mapa.is_empty() and not _regenerando:
		_regenerando = true
		_t_regeneracion = INTERVALO_REGENERACION


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


func _on_jugador_atrapado() -> void:
	print("¡Abaddon te atrapó!")


func _input(event: InputEvent) -> void:
	if jugador_nodo != null and jugador_nodo.esta_muerto:
		return
	# Solo el primer frame de la pulsación (pressed=true, echo=false).
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_W, KEY_UP: _ee_registrar("U")
			KEY_S, KEY_DOWN: _ee_registrar("D")
			KEY_A, KEY_LEFT: _ee_registrar("L")
			KEY_D, KEY_RIGHT: _ee_registrar("R")
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_ee_registrar("A")
			MOUSE_BUTTON_RIGHT:
				var ahora: int = Time.get_ticks_msec()
				var doble: bool = event.double_click or (ahora - _ee_ultimo_der_msec <= 350)
				_ee_ultimo_der_msec = ahora
				_ee_registrar("B", doble)


func _ee_registrar(c: String, doble_der: bool = false) -> void:
	_ee_buffer += c
	if _ee_buffer.length() > _EE_MAX:
		_ee_buffer = _ee_buffer.right(_EE_MAX)
	if _ee_buffer.ends_with(_EE_KONAMI):
		_ee_buffer = ""
		_activar_konami()
	elif doble_der and (_ee_buffer.ends_with(_EE_LLUVIA)
			or _ee_buffer.ends_with(_EE_LLUVIA_RATON)):
		_ee_buffer = ""
		_activar_lluvia()


func _activar_konami() -> void:
	if jugador_nodo == null or jugador_nodo.esta_muerto:
		return
	print("[EasterEgg] Konami activado → teletransporte a la salida")
	_congelar_enemigo(true)
	jugador_nodo.global_position = celda_a_mundo(salida) + Vector3(0.0, 0.1, 0.0)
	jugador_nodo.celda_actual = salida
	if hud != null:
		hud._mostrar("✦ WARP ✦")
	Sonidos.reproducir(jugador_nodo, "ui_comenzar")
	await get_tree().create_timer(0.5).timeout
	_congelar_enemigo(false)
	_on_celda_cambiada(salida)


func _activar_lluvia() -> void:
	if jugador_nodo == null or jugador_nodo.esta_muerto:
		return
	print("[EasterEgg] Lluvia de ítems activada")
	var tipos: Array = Perks.todos()
	var ocupadas: Array[Vector2i] = []
	for v in posiciones_perks.values():
		ocupadas.append(v)
	var celdas: Array[Vector2i] = _celdas_libres_cercanas(
		jugador_nodo.celda_actual, ocupadas, tipos.size())
	for i in tipos.size():
		var tipo: int = tipos[i]
		var celda: Vector2i = celdas[i] if i < celdas.size() else jugador_nodo.celda_actual
		if _perks_en_mapa.has(tipo):
			_perks_en_mapa[tipo].position = celda_a_mundo(celda)
			posiciones_perks[tipo] = celda
		else:
			_crear_perk(tipo, celda)
		ocupadas.append(celda)

	_regenerando = false
	if hud != null:
		hud._mostrar("✦ ITEMS ✦")
	Sonidos.reproducir(jugador_nodo, "recoger_item")


func _celdas_libres_cercanas(origen: Vector2i, ocupadas: Array[Vector2i],
		cantidad: int) -> Array[Vector2i]:
	var resultado: Array[Vector2i] = []
	var vistos: Dictionary = {origen: true}
	var cola: Array[Vector2i] = [origen]
	var cabeza: int = 0
	var filas: int = matriz.size()
	var cols: int = matriz[0].size()
	while cabeza < cola.size() and resultado.size() < cantidad:
		var c: Vector2i = cola[cabeza]
		cabeza += 1
		if c != origen and matriz[c.y][c.x] == 0 and not ocupadas.has(c) \
				and c != salida and c != enemigo:
			resultado.append(c)
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n: Vector2i = c + dir
			if n.y < 0 or n.y >= filas or n.x < 0 or n.x >= cols or vistos.has(n):
				continue
			if matriz[n.y][n.x] != 0:
				continue
			vistos[n] = true
			cola.append(n)
	return resultado


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
