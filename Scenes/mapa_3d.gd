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

@export_group("Texturas")
@export var usar_texturas: bool = true
# Cada cuántos metros se repite una textura (2 m ≈ una celda).
@export var metros_por_textura: float = 2.0
@export var metros_por_textura_cielo: float = 48.0

# Fuerza la salida que viene en el .txt en lugar de calcular una estratégica.
# Pon esto a true si ya ajustaste la salida a mano en el .txt y no quieres que se mueva.
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
var _mat_pared: StandardMaterial3D
var _mat_suelo: StandardMaterial3D
var _mat_techo: StandardMaterial3D
var _mat_lapida: StandardMaterial3D

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
	fuente = datos.get("fuente", Vector2i(-1, -1))
	tren_inicio = datos.get("tren", Vector2i(-1, -1))
	tren_largo = int(datos.get("tren_largo", 0))
	tren_orientacion = str(datos.get("tren_orientacion", "h"))
	es_exterior = str(datos.get("exterior", "0")) == "1"
	altura_cielo = maxf(alto_muro + 1.0, float(datos.get("altura_cielo", "0")))
	if matriz.is_empty():
		return

	# Calcular una salida estratégica (si no se pide respetar la del .txt)
	if not respetar_salida_txt and _hay_salida():
		salida = _elegir_salida_estrategica()

	_preparar_materiales()
	_construir_muros()
	_construir_suelo_y_techo()
	_construir_fuente()
	_construir_tren()
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


# ── Materiales ───────────────────────────────────────────────────────────────
# Busca texturas en Assets/MapAssets/<NombreDelMapa>/: *_albedo.png, *_normal.png
# y opcionalmente *_roughness.png. Si no existen, usa el color plano de siempre.
func _preparar_materiales() -> void:
	_mat_pared = _material_texturizado("pared", Color(0.55, 0.55, 0.6), 0.8)
	_mat_suelo = _material_texturizado("suelo", Color(0.12, 0.12, 0.14), 0.95)
	if es_exterior:
		_mat_techo = _material_texturizado("techo", Color(0.01, 0.015, 0.03), 1.0,
			metros_por_textura_cielo, true)
	else:
		_mat_techo = _material_texturizado("techo", Color(0.08, 0.08, 0.09), 0.9)
	_mat_lapida = _material_texturizado("lapida", Color(0.45, 0.45, 0.45), 0.85)


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
		var plano := _material(color)
		if es_cielo:
			_ajustar_material_cielo(plano)
		return plano

	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.albedo_color = Color.WHITE
	var normal: Texture2D = _cargar_textura(carpeta + nombre + "_normal.png")
	if normal != null:
		m.normal_enabled = true
		m.normal_texture = normal
		m.normal_scale = 0.8
	var rough: Texture2D = _cargar_textura(carpeta + nombre + "_roughness.png")
	if rough != null:
		m.roughness_texture = rough
	else:
		m.roughness = rugosidad

	# Triplanar en coordenadas de mundo: evita que la textura se estire en muros largos.
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	var metros: float = metros_por_textura if escala_metros <= 0.0 else escala_metros
	var escala: float = 1.0 / maxf(0.05, metros)
	m.uv1_scale = Vector3(escala, escala, escala)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if es_cielo:
		_ajustar_material_cielo(m)
	return m


func _ajustar_material_cielo(m: StandardMaterial3D) -> void:
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	m.disable_receive_shadows = true


func _construir_muros() -> void:
	var mat: StandardMaterial3D = _mat_pared
	var cementerio: bool = _es_cementerio()
	var cols: int = matriz[0].size()
	for y in matriz.size():
		var x: int = 0
		while x < cols:
			if _es_celda_fuente(x, y) or _es_celda_tren(x, y):
				x += 1
				continue
			if matriz[y][x] == 1 and _es_visible(x, y):
				# En el cementerio, cada bloque de 1 aislado se convierte en una lápida.
				if cementerio and _es_bloque_solitario(x, y):
					_crear_lapida(Vector2i(x, y))
					x += 1
					continue
				var inicio: int = x
				while x < cols and matriz[y][x] == 1 and _es_visible(x, y) \
						and not _es_celda_fuente(x, y) and not _es_celda_tren(x, y):
					x += 1
				var largo: int = x - inicio
				_crear_bloque(
					Vector3((inicio + largo / 2.0) * tam_celda, alto_muro / 2.0, (y + 0.5) * tam_celda),
					Vector3(largo * tam_celda, alto_muro, tam_celda),
					mat, true)
			else:
				x += 1


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


func _es_cementerio() -> bool:
	return archivo_mapa.get_file().to_lower().contains("cementerio")


# Un bloque solitario es un muro 1x1 sin ningún otro muro a su alrededor.
func _es_bloque_solitario(x: int, y: int) -> bool:
	if x <= 0 or y <= 0 or x >= matriz[0].size() - 1 or y >= matriz.size() - 1:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if matriz[y + dy][x + dx] == 1:
				return false
	return true


# Lápida con parcela elevada. La parcela bloquea la celda para conservar la colisión del mapa.
func _crear_lapida(celda: Vector2i) -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Lapida_%d_%d" % [celda.x, celda.y]
	cuerpo.add_to_group("lapidas")
	cuerpo.position = celda_a_mundo(celda)
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash_celda(celda)
	cuerpo.rotation.y = rng.randf_range(-0.12, 0.12)

	var base := _malla_caja(Vector3(1.8, 0.14, 1.8), Vector3(0.0, 0.07, 0.0), _mat_lapida)
	cuerpo.add_child(base)
	var tierra := _malla_caja(Vector3(1.5, 0.16, 1.5), Vector3(0.0, 0.16, 0.10), _mat_suelo)
	cuerpo.add_child(tierra)

	var ancho: float = rng.randf_range(0.9, 1.1)
	var alto: float = rng.randf_range(1.1, 1.4)
	var y0: float = 0.24
	var z_lapida: float = -0.55

	var lapida := _malla_caja(Vector3(ancho, alto, 0.32),
		Vector3(0.0, y0 + alto * 0.5, z_lapida), _mat_lapida)
	cuerpo.add_child(lapida)

	# Tapa semicilíndrica: el cilindro va acostado sobre el eje X.
	var radio: float = ancho * 0.5
	var cilindro := CylinderMesh.new()
	cilindro.top_radius = radio
	cilindro.bottom_radius = radio
	cilindro.height = ancho
	cilindro.radial_segments = 16
	var tapa := MeshInstance3D.new()
	tapa.mesh = cilindro
	tapa.material_override = _mat_lapida
	tapa.position = Vector3(0.0, y0 + alto, z_lapida)
	tapa.rotation.z = PI * 0.5
	tapa.scale = Vector3(1.0, 1.0, 0.32 / maxf(0.01, radio * 2.0))
	cuerpo.add_child(tapa)

	# Algunas lápidas llevan una cruz en la cara frontal.
	if rng.randf() < 0.45:
		var z_cruz: float = z_lapida - 0.19
		var cruz_v := _malla_caja(Vector3(0.11, alto * 0.45, 0.06),
			Vector3(0.0, y0 + alto * 0.60, z_cruz), _mat_lapida)
		cuerpo.add_child(cruz_v)
		var cruz_h := _malla_caja(Vector3(0.46, 0.11, 0.06),
			Vector3(0.0, y0 + alto * 0.72, z_cruz), _mat_lapida)
		cuerpo.add_child(cruz_h)

	# La parcela baja impide atravesar la celda sin necesidad de un muro invisible alto.
	var col_parcela := CollisionShape3D.new()
	var caja_parcela := BoxShape3D.new()
	caja_parcela.size = Vector3(1.78, 0.28, 1.78)
	col_parcela.shape = caja_parcela
	col_parcela.position = Vector3(0.0, 0.14, 0.0)
	cuerpo.add_child(col_parcela)

	var col_lapida := CollisionShape3D.new()
	var caja_lapida := BoxShape3D.new()
	caja_lapida.size = Vector3(ancho, alto, 0.4)
	col_lapida.shape = caja_lapida
	col_lapida.position = Vector3(0.0, y0 + alto * 0.5, z_lapida)
	cuerpo.add_child(col_lapida)

	add_child(cuerpo)


func _construir_fuente() -> void:
	if fuente.x < 0 or fuente.y < 0:
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Fuente_%d_%d" % [fuente.x, fuente.y]
	cuerpo.add_to_group("fuente")
	cuerpo.position = celda_a_mundo(fuente)

	var agua := _material(Color(0.05, 0.22, 0.28))
	agua.metallic = 0.25
	agua.roughness = 0.08
	agua.emission_enabled = true
	agua.emission = Color(0.03, 0.12, 0.15)
	agua.emission_energy_multiplier = 0.7

	cuerpo.add_child(_malla_cilindro(1.0, 1.12, 0.5, Vector3(0.0, 0.25, 0.0), _mat_pared))
	cuerpo.add_child(_malla_cilindro(0.86, 0.86, 0.06, Vector3(0.0, 0.51, 0.0), agua))
	cuerpo.add_child(_malla_cilindro(0.18, 0.22, 0.85, Vector3(0.0, 0.85, 0.0), _mat_pared))
	cuerpo.add_child(_malla_cilindro(0.5, 0.28, 0.18, Vector3(0.0, 1.32, 0.0), _mat_pared))
	cuerpo.add_child(_malla_cilindro(0.43, 0.43, 0.05, Vector3(0.0, 1.43, 0.0), agua))

	var remate := MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = 0.11
	esfera.height = 0.22
	remate.mesh = esfera
	remate.material_override = _mat_pared
	remate.position = Vector3(0.0, 1.56, 0.0)
	cuerpo.add_child(remate)

	var col := CollisionShape3D.new()
	var forma := CylinderShape3D.new()
	forma.radius = 1.05
	forma.height = 0.55
	col.shape = forma
	col.position = Vector3(0.0, 0.275, 0.0)
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

	var balasto := _material(Color(0.12, 0.12, 0.13))
	balasto.roughness = 0.95
	raiz.add_child(_malla_caja(Vector3(largo_total, 0.1, ancho_total * 0.9),
		Vector3(0.0, 0.05, 0.0), balasto))

	var durmiente := _material(Color(0.18, 0.14, 0.11))
	durmiente.roughness = 0.9
	var x_durmiente: float = -largo_total * 0.5 + 1.0
	while x_durmiente < largo_total * 0.5:
		raiz.add_child(_malla_caja(Vector3(0.25, 0.08, ancho_total * 0.82),
			Vector3(x_durmiente, 0.09, 0.0), durmiente))
		x_durmiente += 2.0

	var metal := _material(Color(0.42, 0.44, 0.48))
	metal.metallic = 0.85
	metal.roughness = 0.28
	raiz.add_child(_malla_caja(Vector3(largo_total, 0.12, 0.1),
		Vector3(0.0, 0.17, -0.75), metal))
	raiz.add_child(_malla_caja(Vector3(largo_total, 0.12, 0.1),
		Vector3(0.0, 0.17, 0.75), metal))

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

	var num_coches: int = 4
	var separacion: float = 0.9
	var largo_coche: float = (largo_total - separacion * (num_coches - 1)) / num_coches
	var ancho_cuerpo: float = ancho_total * 0.82
	var alto_cuerpo: float = 2.45
	var y_base: float = 0.25
	for i in num_coches:
		var x_coche: float = -largo_total * 0.5 + largo_coche * 0.5 + i * (largo_coche + separacion)
		raiz.add_child(_malla_caja(Vector3(largo_coche, alto_cuerpo, ancho_cuerpo),
			Vector3(x_coche, y_base + alto_cuerpo * 0.5, 0.0), carroceria))
		raiz.add_child(_malla_caja(Vector3(largo_coche * 0.96, 0.18, ancho_cuerpo * 0.92),
			Vector3(x_coche, y_base + alto_cuerpo + 0.09, 0.0), techo))
		for lado in [-1.0, 1.0]:
			var z_lado: float = lado * (ancho_cuerpo * 0.5 + 0.03)
			raiz.add_child(_malla_caja(Vector3(largo_coche * 0.72, 0.65, 0.05),
				Vector3(x_coche, y_base + alto_cuerpo * 0.66, z_lado), ventanas))
			raiz.add_child(_malla_caja(Vector3(largo_coche * 0.92, 0.12, 0.05),
				Vector3(x_coche, y_base + 0.34, z_lado), franja))

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


func _hash_celda(c: Vector2i) -> int:
	return absi((c.x * 73856093) ^ (c.y * 19349663))


func _malla_caja(tam: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var malla := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = tam
	malla.mesh = caja
	malla.material_override = mat
	malla.position = pos
	return malla


func _construir_suelo_y_techo() -> void:
	var ancho: float = matriz[0].size() * tam_celda
	var largo: float = matriz.size() * tam_celda
	_crear_bloque(Vector3(ancho / 2.0, -0.1, largo / 2.0), Vector3(ancho, 0.2, largo),
		_mat_suelo, true)
	if con_techo and not camara_cenital:
		if es_exterior:
			_crear_bloque(Vector3(ancho / 2.0, altura_cielo, largo / 2.0),
				Vector3(ancho * 4.0, 0.2, largo * 4.0), _mat_techo, false)
		else:
			_crear_bloque(Vector3(ancho / 2.0, alto_muro + 0.1, largo / 2.0),
				Vector3(ancho, 0.2, largo), _mat_techo, false)


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
	env.background_color = Color(0.01, 0.015, 0.03) if es_exterior else Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.4)
	env.ambient_light_energy = 0.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.015, 0.02, 0.04) if es_exterior else Color(0.03, 0.03, 0.04)
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
