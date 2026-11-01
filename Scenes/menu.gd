extends Node3D
# Menú principal 3D al estilo Persona/Atlus.
# El fondo es el mapa del cementerio real (con luna, niebla, luces que parpadean y ceniza).
# Cada pantalla del menú tiene su propio "plano" de cámara: al pulsar una opción, la cámara viaja
# a otro ángulo del mismo escenario y aparecen las opciones siguientes.
# Escena: nodo raíz Node3D + este script, guardada como Scenes/menu.tscn.

const TITULO: String = "EL CAMINO MÁS CORTO"
const SUBTITULO: String = "Él siempre encuentra la ruta hacia ti"
# Fuente opcional muy parecida a la de Persona: "Anton" (licencia libre, fonts.google.com).
const FUENTE_UI: String = "res://Assets/Fonts/Anton-Regular.ttf"
const MAPA_ESCENARIO: String = "res://Maps/mapa2_cementerio.txt"
const TAM_CELDA: float = 2.0
const NIEBLA_VOLUMETRICA: bool = false   # ponla en true si tu PC lo aguanta (solo renderer Forward+)

const SANGRE := Color(0.78, 0.04, 0.06)
const HUESO := Color(0.94, 0.91, 0.84)
const NEGRO := Color(0.03, 0.02, 0.02)

# Planos de cámara. "desde" y "hacia" = Vector3(columna, altura en metros, fila); columna y fila
# en unidades de celda (x.5 = centro de la celda). Todos los "desde" caen en celdas libres.
const PLANOS: Dictionary = {
	"titulo":    {"desde": Vector3(18.5, 1.3, 28.5), "hacia": Vector3(19.5, 2.4, 22.5), "fov": 62.0, "niebla": 0.028},
	"principal": {"desde": Vector3(6.5, 1.1, 11.5),  "hacia": Vector3(6.5, 1.8, 7.0),   "fov": 70.0, "niebla": 0.035},
	"controles": {"desde": Vector3(36.5, 7.5, 3.5),  "hacia": Vector3(20.5, 0.5, 15.5), "fov": 60.0, "niebla": 0.020},
	"modo":      {"desde": Vector3(2.5, 1.4, 28.5),  "hacia": Vector3(30.5, 1.6, 28.5), "fov": 68.0, "niebla": 0.030},
	"mapa":      {"desde": Vector3(3.0, 14.0, 37.5), "hacia": Vector3(21.0, 0.0, 20.0), "fov": 55.0, "niebla": 0.012},
	"confirmar": {"desde": Vector3(19.5, 1.4, 21.5), "hacia": Vector3(19.5, 1.7, 15.5), "fov": 72.0, "niebla": 0.040},
}

const TEXTO_CONTROLES: String = "W A S D  —  moverse\nMouse / flechas  —  mirar\nShift  —  correr\n1 / 2  —  linterna / pistola\nR  —  radar\nClic izquierdo  —  disparar\nM  —  volver al menú"

# Cámara
var _camara: Camera3D
var _env: Environment
var _pose: Transform3D = Transform3D.IDENTITY
var fov_actual: float = 62.0      # sin guion bajo: se anima con tweens
var niebla_actual: float = 0.03
var _tw_cam: Tween
var _t: float = 0.0
var _luces: Array = []

# Menú
var _fuente: Font
var _pantalla: String = ""
var _def: Dictionary = {}
var _opciones: Array[MenuOpcion] = []
var _sel: int = 0
var _bloqueado: bool = false

# Interfaz
var _col_izq: VBoxContainer
var _panel_info: PanelContainer
var _info_titulo: Label
var _info_texto: Label
var _bloque_titulo: Control
var _titulo_lbl: Label
var _lbl_pulsa: Label
var _flash: ColorRect
var _fade: ColorRect


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # el juego lo deja capturado
	Partida.activa = false
	_cargar_fuente()
	_crear_escenario()
	_crear_ambiente()
	_crear_luces()
	_crear_particulas()
	_crear_camara()
	_crear_ui()

	_pantalla = "titulo"                 # arranca directo en el plano del título
	_def = _definir("titulo")
	var p: Dictionary = PLANOS["titulo"]
	_pose = _transform_plano("titulo")
	fov_actual = p["fov"]
	niebla_actual = p["niebla"]
	_reconstruir_ui()
	create_tween().tween_property(_fade, "color:a", 0.0, 1.2)   # sale de la oscuridad


# ---------------------------------------------------------------- Escenario 3D

func _crear_escenario() -> void:
	var mapa := Mapa3D.new()
	mapa.archivo_mapa = MAPA_ESCENARIO
	mapa.tam_celda = TAM_CELDA
	mapa.solo_escenografia = true   # solo muros y suelo
	mapa.con_techo = false          # cielo abierto
	add_child(mapa)


func _crear_ambiente() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.025, 0.05)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.20, 0.24, 0.38)
	_env.ambient_light_energy = 0.35
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.05, 0.06, 0.10)
	_env.fog_density = niebla_actual
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	if NIEBLA_VOLUMETRICA:
		_env.volumetric_fog_enabled = true
		_env.volumetric_fog_density = 0.03
		_env.volumetric_fog_albedo = Color(0.5, 0.55, 0.7)
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	# Luna: luz direccional azulada con sombras largas, más un disco visible en el cielo.
	var luna := DirectionalLight3D.new()
	luna.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	luna.light_color = Color(0.55, 0.65, 1.0)
	luna.light_energy = 0.55
	luna.shadow_enabled = true
	luna.directional_shadow_max_distance = 120.0
	add_child(luna)
	var dir: Vector3 = luna.basis * Vector3(0.0, 0.0, -1.0)   # hacia dónde viaja la luz
	var disco := MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = 7.0
	esfera.height = 14.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.9, 1.0)
	mat.disable_fog = true
	disco.mesh = esfera
	disco.material_override = mat
	disco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disco.position = Vector3(40.0, 0.0, 40.0) - dir * 160.0
	add_child(disco)


func _crear_luces() -> void:
	# [posición (columna, altura, fila), color, energía, alcance]
	var datos: Array = [
		[Vector3(6.5, 1.2, 9.0),   Color(1.0, 0.15, 0.10), 2.4, 9.0],   # cripta: roja
		[Vector3(19.5, 1.6, 19.5), Color(0.40, 0.95, 0.65), 2.0, 8.0],  # mausoleo: verde pálido
		[Vector3(10.5, 1.2, 26.0), Color(1.00, 0.60, 0.25), 1.8, 8.0],  # farol cálido
		[Vector3(30.5, 1.2, 28.5), Color(1.00, 0.60, 0.25), 1.8, 8.0],  # farol cálido
	]
	for d in datos:
		var p: Vector3 = d[0]
		var luz := OmniLight3D.new()
		luz.position = Vector3(p.x * TAM_CELDA, p.y, p.z * TAM_CELDA)
		luz.light_color = d[1]
		luz.omni_range = d[3]
		add_child(luz)
		_luces.append({"luz": luz, "base": d[2], "fase": randf() * TAU})


func _crear_particulas() -> void:   # ceniza flotando en el aire
	var p := CPUParticles3D.new()
	p.amount = 500
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(40.0, 5.0, 40.0)
	p.position = Vector3(40.0, 5.0, 40.0)
	p.direction = Vector3(0.0, -1.0, 0.0)
	p.spread = 25.0
	p.gravity = Vector3(0.15, -0.02, 0.05)
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.5
	var m := SphereMesh.new()
	m.radius = 0.03
	m.height = 0.06
	m.radial_segments = 4
	m.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.85, 0.9, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	add_child(p)


func _crear_camara() -> void:
	_camara = Camera3D.new()
	add_child(_camara)
	_camara.current = true
	_camara.near = 0.05


# ---------------------------------------------------------------- Cámara

func _transform_plano(clave: String) -> Transform3D:
	var p: Dictionary = PLANOS[clave]
	var desde: Vector3 = p["desde"]
	var hacia: Vector3 = p["hacia"]
	var d := Vector3(desde.x * TAM_CELDA, desde.y, desde.z * TAM_CELDA)
	var h := Vector3(hacia.x * TAM_CELDA, hacia.y, hacia.z * TAM_CELDA)
	return Transform3D(Basis.IDENTITY, d).looking_at(h, Vector3.UP)


func _ir_a_plano(clave: String) -> void:
	var p: Dictionary = PLANOS[clave]
	if _tw_cam != null:
		_tw_cam.kill()
	_tw_cam = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw_cam.tween_method(
		_mover_camara.bind(_pose, _transform_plano(clave), fov_actual, p["fov"], niebla_actual, p["niebla"]),
		0.0, 1.0, 1.4)


# w va de 0 a 1; el resto son los valores de partida y de llegada.
func _mover_camara(w: float, t0: Transform3D, t1: Transform3D, fov0: float, fov1: float, nb0: float, nb1: float) -> void:
	_pose = t0.interpolate_with(t1, w)
	fov_actual = lerpf(fov0, fov1, w) + sin(w * PI) * 14.0   # "tirón" de lente durante el viaje
	niebla_actual = lerpf(nb0, nb1, w)


func _destello() -> void:
	_flash.color.a = 0.55
	_flash.create_tween().tween_property(_flash, "color:a", 0.0, 0.35)


# ---------------------------------------------------------------- Pantallas

# Cada pantalla: plano de cámara, encabezado, opciones (texto + acción), panel de info y a dónde vuelve.
func _definir(nombre: String) -> Dictionary:
	match nombre:
		"titulo":
			return {"plano": "titulo", "encabezado": "", "opciones": [], "atras": ""}
		"principal":
			return {
				"plano": "principal", "encabezado": "MENÚ", "atras": "titulo",
				"opciones": [
					{"texto": "JUGAR", "accion": func(): _mostrar("modo")},
					{"texto": "CONTROLES", "accion": func(): _mostrar("controles")},
					{"texto": "SALIR", "accion": func(): get_tree().quit()},
				],
				"info": [
					["JUGAR", "Elige un modo de juego y un mapa. Él ya te está esperando."],
					["CONTROLES", "Repasa cómo moverte, mirar y usar tus perks."],
					["SALIR", "Cerrar el juego."],
				],
			}
		"controles":
			return {
				"plano": "controles", "encabezado": "CONTROLES", "atras": "principal",
				"opciones": [{"texto": "VOLVER", "accion": func(): _mostrar("principal")}],
				"info": [["CONTROLES", TEXTO_CONTROLES]],
			}
		"modo":
			var ops: Array = []
			var info: Array = []
			for i in Partida.MODOS.size():
				var m: Dictionary = Partida.MODOS[i]
				ops.append({"texto": m["nombre"], "accion": _elegir_modo.bind(i)})
				info.append([m["nombre"], m["desc"]])
			return {"plano": "modo", "encabezado": "MODO DE JUEGO", "atras": "principal",
				"opciones": ops, "info": info, "inicio": Partida.modo}
		"mapa":
			var ops: Array = []
			var info: Array = []
			for i in Partida.MAPAS.size():
				var m: Dictionary = Partida.MAPAS[i]
				ops.append({"texto": m["nombre"], "accion": _elegir_mapa.bind(i)})
				info.append([m["nombre"], "%s\n\n%s  ·  %d nodos en el grafo" % [m["desc"], m["tam"], m["nodos"]]])
			return {"plano": "mapa", "encabezado": "ELIGE EL MAPA", "atras": "modo",
				"opciones": ops, "info": info, "inicio": Partida.indice_mapa}
		"confirmar":
			var resumen: String = "Modo: %s\nMapa: %s\n\n%s" % [
				Partida.nombre_modo(), Partida.MAPAS[Partida.indice_mapa]["nombre"], Partida.MODOS[Partida.modo]["desc"]]
			return {
				"plano": "confirmar", "encabezado": "¿LISTO?", "atras": "mapa",
				"opciones": [
					{"texto": "COMENZAR", "accion": _comenzar},
					{"texto": "VOLVER", "accion": func(): _mostrar("mapa")},
				],
				"info": [["TU PARTIDA", resumen]],
			}
	return {}


func _mostrar(nombre: String) -> void:
	if _bloqueado:
		return
	_pantalla = nombre
	_def = _definir(nombre)
	_ir_a_plano(_def["plano"])
	_destello()
	_reconstruir_ui()


func _elegir_modo(i: int) -> void:
	Partida.modo = i
	_mostrar("mapa")


func _elegir_mapa(i: int) -> void:
	Partida.indice_mapa = i
	_mostrar("confirmar")


func _atras() -> void:
	var a: String = _def.get("atras", "")
	if a != "":
		_mostrar(a)


func _comenzar() -> void:
	if _bloqueado:
		return
	_bloqueado = true
	Partida.activa = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_fade, "color:a", 1.0, 0.9)
	tw.tween_property(self, "fov_actual", 28.0, 0.9)   # zoom hacia la oscuridad
	tw.chain().tween_callback(func(): get_tree().change_scene_to_file(Partida.ESCENA_JUEGO))


# ---------------------------------------------------------------- Interfaz

func _reconstruir_ui() -> void:
	for h in _col_izq.get_children():
		_col_izq.remove_child(h)
		h.queue_free()
	_opciones.clear()
	_panel_info.visible = false
	_bloque_titulo.visible = (_pantalla == "titulo")

	var retraso: float = 0.3   # las opciones entran mientras la cámara ya va viajando
	var enc: String = _def.get("encabezado", "")
	if enc != "":
		var banner := MenuOpcion.new()
		banner.configurar(enc, _fuente, 44, MenuOpcion.Estilo.BANNER, 440.0, 70.0)
		_col_izq.add_child(banner)
		_entrada(banner, retraso)
		retraso += 0.07

	var lista: Array = _def.get("opciones", [])
	for i in lista.size():
		var op := MenuOpcion.new()
		op.configurar(lista[i]["texto"], _fuente, 34, MenuOpcion.Estilo.OPCION, 440.0, 62.0)
		var envoltorio := MarginContainer.new()   # escalona cada opción un poco más a la derecha
		envoltorio.mouse_filter = Control.MOUSE_FILTER_IGNORE
		envoltorio.add_theme_constant_override("margin_left", i * 26)
		envoltorio.add_child(op)
		_col_izq.add_child(envoltorio)
		op.enfocada.connect(_seleccionar.bind(i))
		op.elegida.connect(_aceptar.bind(i))
		_opciones.append(op)
		_entrada(op, retraso)
		retraso += 0.07

	if not _opciones.is_empty():
		_seleccionar(_def.get("inicio", 0))


func _entrada(c: Control, retraso: float) -> void:
	c.scale = Vector2(0.01, 1.0)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.32).set_delay(retraso) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.2).set_delay(retraso)


func _seleccionar(i: int) -> void:
	if _opciones.is_empty():
		return
	_sel = clampi(i, 0, _opciones.size() - 1)
	for k in _opciones.size():
		_opciones[k].seleccionada = (k == _sel)
	_actualizar_info()


func _aceptar(i: int) -> void:
	if _bloqueado or _opciones.is_empty():
		return
	_sel = i
	var accion: Callable = _def["opciones"][i]["accion"]
	accion.call()


func _actualizar_info() -> void:
	var info: Array = _def.get("info", [])
	if info.is_empty():
		_panel_info.visible = false
		return
	var par: Array = info[mini(_sel, info.size() - 1)]
	_info_titulo.text = par[0]
	_info_texto.text = par[1]
	if not _panel_info.visible:   # primera vez en esta pantalla: aparece con un pequeño retraso
		_panel_info.visible = true
		_panel_info.modulate.a = 0.0
		_panel_info.create_tween().tween_property(_panel_info, "modulate:a", 1.0, 0.3).set_delay(0.5)


func _unhandled_input(event: InputEvent) -> void:
	if _bloqueado:
		return
	var tecla: bool = event is InputEventKey and event.pressed and not event.echo
	var clic: bool = event is InputEventMouseButton and event.pressed
	if _pantalla == "titulo":
		if tecla or clic:
			_mostrar("principal")
		return
	if tecla:
		match event.physical_keycode:
			KEY_UP, KEY_W:
				_seleccionar(posmod(_sel - 1, _opciones.size()))
			KEY_DOWN, KEY_S:
				_seleccionar(posmod(_sel + 1, _opciones.size()))
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_aceptar(_sel)
			KEY_ESCAPE, KEY_BACKSPACE:
				_atras()
	elif clic and event.button_index == MOUSE_BUTTON_RIGHT:
		_atras()


# ---------------------------------------------------------------- Construcción de la interfaz

func _cargar_fuente() -> void:
	if ResourceLoader.exists(FUENTE_UI):
		_fuente = load(FUENTE_UI)
	else:
		var s := SystemFont.new()
		s.font_names = PackedStringArray(["Impact", "Haettenschweiler", "Arial Black", "Arial"])
		s.font_weight = 800
		_fuente = s


func _lbl(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", _fuente)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _crear_vineta() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.12), Color(0, 0, 0, 0.9)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


func _crear_ui() -> void:
	var capa := CanvasLayer.new()
	add_child(capa)

	var vineta := TextureRect.new()
	vineta.texture = _crear_vineta()
	vineta.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vineta.stretch_mode = TextureRect.STRETCH_SCALE
	vineta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(vineta)
	vineta.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var raiz := Control.new()
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(raiz)
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Columna izquierda (opciones) y derecha (panel de información).
	var margen := MarginContainer.new()
	margen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margen.add_theme_constant_override("margin_left", 80)
	margen.add_theme_constant_override("margin_right", 80)
	margen.add_theme_constant_override("margin_top", 70)
	margen.add_theme_constant_override("margin_bottom", 70)
	raiz.add_child(margen)
	margen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fila := HBoxContainer.new()
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margen.add_child(fila)

	_col_izq = VBoxContainer.new()
	_col_izq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col_izq.alignment = BoxContainer.ALIGNMENT_CENTER
	_col_izq.add_theme_constant_override("separation", 14)
	_col_izq.custom_minimum_size = Vector2(560, 0)
	fila.add_child(_col_izq)

	var relleno := Control.new()
	relleno.mouse_filter = Control.MOUSE_FILTER_IGNORE
	relleno.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(relleno)

	var col_der := VBoxContainer.new()
	col_der.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_der.alignment = BoxContainer.ALIGNMENT_CENTER
	fila.add_child(col_der)
	_crear_panel_info(col_der)

	_crear_bloque_titulo(raiz)

	var pista := _lbl("MOUSE o W/S  elegir      CLIC o ENTER  aceptar      ESC o CLIC DERECHO  volver",
		16, HUESO.darkened(0.35))
	pista.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	raiz.add_child(pista)
	pista.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	pista.offset_left = -780.0
	pista.offset_right = -40.0
	pista.offset_top = -46.0
	pista.offset_bottom = -16.0

	_flash = ColorRect.new()   # destello rojo al cambiar de pantalla
	_flash.color = Color(0.85, 0.05, 0.06, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_fade = ColorRect.new()    # fundido a negro (entrada y salida)
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _crear_panel_info(padre: Control) -> void:
	_panel_info = PanelContainer.new()
	_panel_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_info.custom_minimum_size = Vector2(430, 0)
	_panel_info.rotation_degrees = -1.5
	var st := StyleBoxFlat.new()
	st.bg_color = Color(NEGRO, 0.9)
	st.border_color = SANGRE
	st.set_border_width_all(2)
	st.border_width_left = 10
	st.set_content_margin_all(22)
	_panel_info.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 12)
	_panel_info.add_child(v)
	_info_titulo = _lbl("", 38, SANGRE)
	_info_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(_info_titulo)
	_info_texto = _lbl("", 21, HUESO)
	_info_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_info_texto.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_info_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_texto.custom_minimum_size = Vector2(380, 0)
	v.add_child(_info_texto)
	_panel_info.visible = false
	padre.add_child(_panel_info)


func _crear_bloque_titulo(raiz: Control) -> void:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 80)
	m.add_theme_constant_override("margin_right", 80)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 120)
	raiz.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bloque_titulo = m

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)

	_titulo_lbl = _lbl(TITULO, 104, HUESO)
	_titulo_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_titulo_lbl.add_theme_constant_override("outline_size", 12)
	_titulo_lbl.add_theme_color_override("font_shadow_color", SANGRE)
	_titulo_lbl.add_theme_constant_override("shadow_offset_x", 8)
	_titulo_lbl.add_theme_constant_override("shadow_offset_y", 8)
	_titulo_lbl.rotation_degrees = -3.0
	v.add_child(_titulo_lbl)
	v.add_child(_lbl(SUBTITULO, 28, SANGRE))
	var espacio := Control.new()
	espacio.custom_minimum_size = Vector2(0, 30)
	espacio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(espacio)
	_lbl_pulsa = _lbl("PULSA CUALQUIER TECLA", 30, HUESO)
	v.add_child(_lbl_pulsa)


# ---------------------------------------------------------------- Animación por frame

func _process(delta: float) -> void:
	_t += delta

	# Cámara: deriva lenta y un leve balanceo, siempre en movimiento.
	var deriva := Vector3(sin(_t * 0.37) * 0.22, sin(_t * 0.29) * 0.10,
		cos(_t * 0.31) * 0.22 - sin(_t * 0.15) * 0.5)
	var giro := Basis.from_euler(Vector3(sin(_t * 0.23) * 0.010, sin(_t * 0.17) * 0.018, sin(_t * 0.21) * 0.008))
	_camara.global_transform = Transform3D(_pose.basis * giro, _pose.origin + _pose.basis * deriva)
	_camara.fov = fov_actual
	_env.fog_density = niebla_actual

	# Luces defectuosas.
	for l in _luces:
		var luz: OmniLight3D = l["luz"]
		var f: float = 0.72 + 0.18 * sin(_t * 9.0 + l["fase"]) + 0.10 * sin(_t * 23.0 + l["fase"] * 2.0)
		if randf() < 0.008:
			f *= 0.15
		luz.light_energy = l["base"] * f

	# Título: parpadeo ocasional y mensaje que late.
	if _bloque_titulo.visible:
		_titulo_lbl.modulate.a = randf_range(0.3, 0.6) if randf() < 0.01 else 0.95
		_lbl_pulsa.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 4.0))
