class_name HUD
extends CanvasLayer
# HUD estilo Doom con menú de pausa (ESC), pantalla de GAME OVER y corrección de mira.
#
# ASSETS PENDIENTES:
#   Sprite manos / linterna  → res://Assets/Chars/LANTERN_recolor2.png
#   Sprite manos / pistola   → res://Assets/Chars/pistol_hand_recolor.png
#   Sprite flash de disparo  → res://Assets/Chars/SHOOT_recolor.png
#   Sprite manos muertas     → res://Assets/Chars/DEAD_HAN_recolor2.png
#   Sprite Abaddon 2D        → res://Assets/Chars/abaddon_sprite.png  (asignar en enemigo.gd)
#
# TAMAÑOS DE SPRITE (ajusta aquí si se ven muy pequeños o grandes):
const MANO_ALTO_RATIO: float    = 0.68   # fracción de la altura de pantalla que ocupa la mano
const MANO_OFFSET_X: float      = 0.12   # desplazamiento lateral (0 = centrado; positivo = derecha)
const MANO_OFFSET_Y: float      = 0.88   # qué tanto de la mano asoma por debajo (mayor = más)
const PISTOLA_OFFSET_X: float   = 0.08   # la pistola se desplaza un poco a la derecha del centro
const PISTOLA_OFFSET_Y: float   = 0.92   # la pistola asoma un poco más

const ALTO_BARRA: float = 84.0
const COLOR_FONDO := Color(0.14, 0.11, 0.10)
const COLOR_BORDE := Color(0.45, 0.12, 0.10)
const COLOR_ROJO := Color(0.85, 0.12, 0.10)
const PERKS: Array = [Perks.Tipo.PISTOLA, Perks.Tipo.RADAR, Perks.Tipo.ESCUDO]

const SHADER_ROJO: String = """
shader_type canvas_item;
uniform sampler2D pantalla : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensidad = 0.0;
void fragment() {
	vec3 c = texture(pantalla, SCREEN_UV).rgb;
	float vig = smoothstep(0.15, 0.85, length(SCREEN_UV - vec2(0.5)) * 1.35);
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 rojo = vec3(g * 1.4 + 0.08, g * 0.16, g * 0.16);
	float k = clamp(intensidad * (0.45 + 0.75 * vig), 0.0, 1.0);
	vec3 r = mix(c, rojo, k * 0.9);
	r += vec3(0.35, 0.0, 0.0) * vig * intensidad;
	float pulso = 0.92 + 0.08 * sin(TIME * (3.0 + 6.0 * intensidad));
	COLOR = vec4(r * pulso, 1.0);
}
"""

const SHADER_INVERTIDO: String = """
shader_type canvas_item;
uniform sampler2D pantalla : hint_screen_texture, repeat_disable, filter_linear;
uniform float fuerza = 1.0;
void fragment() {
	vec3 c = texture(pantalla, SCREEN_UV).rgb;
	COLOR = vec4(mix(c, vec3(1.0) - c, fuerza), 1.0);
}
"""

var jugador: Jugador
var enemigo: Node3D
var desliz: float = 0.0

var _raiz: Control
var _mano: TextureRect
var _muzzle_flash: TextureRect
var _mano_muerta: TextureRect
var _tex_linterna: Texture2D
var _tex_pistola: Texture2D
var _tex_muzzle: Texture2D
var _tex_dead_hands: Texture2D
var _radar: RadarHUD
var _mira: Control          # ahora es un Control con cruz en lugar de un solo ColorRect
var _flash: ColorRect
var _lbl_mensaje: Label
var _lbl_arma: Label
var _fx_rojo: ColorRect
var _pentagrama: MenuSigilo
var _fx_invertido: ColorRect
var _lbl_huida: Label
var _slots: Dictionary = {}
var _retroceso: float = 0.0
var _t_bob: float = 0.0
var _mensaje_t: float = 0.0
var _muzzle_t: float = 0.0

# Stamina bar
var _barra_stamina: ColorRect
var _relleno_stamina: ColorRect

# Game-over
var _pantalla_gameover: Control
var _gameover_visible: bool = false
var _gameover_alpha: float = 0.0

# Menú de pausa
var _menu_pausa: Control
var _pausado: bool = false


func _ready() -> void:
	_tex_linterna = load("res://Assets/Chars/LANTERN_recolor2.png")
	_tex_pistola  = load("res://Assets/Chars/pistol_hand_recolor.png")
	if ResourceLoader.exists("res://Assets/Chars/SHOOT_recolor.png"):
		_tex_muzzle = load("res://Assets/Chars/SHOOT_recolor.png")
	if ResourceLoader.exists("res://Assets/Chars/DEAD_HAN_recolor2.png"):
		_tex_dead_hands = load("res://Assets/Chars/DEAD_HAN_recolor2.png")

	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raiz)
	_raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_crear_efecto_rojo()
	_crear_mano()
	_crear_muzzle_flash()
	_crear_mano_muerta()
	_crear_flash()
	_crear_barra()
	_crear_radar()
	_crear_mira()
	_crear_mensaje()
	_crear_efecto_invertido()
	_crear_pantalla_gameover()
	_crear_menu_pausa()


func conectar(j: Jugador, e: Node3D) -> void:
	jugador = j
	enemigo = e
	_radar.jugador = j
	_radar.objetivo = e
	# Pasar referencia del mapa al radar para el minimapa y la ruta
	var mapa := j.get_parent()
	if mapa is Mapa3D:
		_radar.mapa_ref = mapa
	j.perk_recogido.connect(_on_perk_recogido)
	j.arma_cambiada.connect(_on_arma_cambiada)
	j.disparo_realizado.connect(_on_disparo)
	j.escudo_roto.connect(_on_escudo_roto)
	j.jugador_muerto.connect(_on_jugador_muerto)
	_actualizar_textura()


# ---------- Construcción ----------

func _crear_mano() -> void:
	_mano = TextureRect.new()
	_mano.texture = _tex_linterna
	_mano.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mano.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mano.stretch_mode = TextureRect.STRETCH_SCALE
	_mano.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_mano)


func _crear_muzzle_flash() -> void:
	_muzzle_flash = TextureRect.new()
	_muzzle_flash.texture = _tex_muzzle
	_muzzle_flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_muzzle_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_muzzle_flash.stretch_mode = TextureRect.STRETCH_SCALE
	_muzzle_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_muzzle_flash.visible = false
	_raiz.add_child(_muzzle_flash)


func _crear_mano_muerta() -> void:
	_mano_muerta = TextureRect.new()
	_mano_muerta.texture = _tex_dead_hands
	_mano_muerta.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mano_muerta.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mano_muerta.stretch_mode = TextureRect.STRETCH_SCALE
	_mano_muerta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mano_muerta.visible = false
	_raiz.add_child(_mano_muerta)


func _crear_flash() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.85, 0.4, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _crear_barra() -> void:
	var barra := PanelContainer.new()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COLOR_FONDO
	estilo.border_color = COLOR_BORDE
	estilo.border_width_top = 4
	estilo.set_content_margin_all(8)
	barra.add_theme_stylebox_override("panel", estilo)
	barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(barra)
	barra.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	barra.offset_top = -ALTO_BARRA
	barra.offset_bottom = 0.0

	var fila := HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_CENTER
	fila.add_theme_constant_override("separation", 22)
	barra.add_child(fila)

	_lbl_arma = _etiqueta("", 24, COLOR_ROJO)
	_lbl_arma.custom_minimum_size = Vector2(190, 0)
	fila.add_child(_lbl_arma)
	for tipo in PERKS:
		fila.add_child(_crear_slot(tipo))

	# Stamina
	var col_stamina := VBoxContainer.new()
	col_stamina.alignment = BoxContainer.ALIGNMENT_CENTER
	col_stamina.custom_minimum_size = Vector2(100, 0)
	fila.add_child(col_stamina)
	col_stamina.add_child(_etiqueta("STAMINA", 11, Color(0.7, 0.7, 0.7)))
	var fondo_st := ColorRect.new()
	fondo_st.color = Color(0.15, 0.15, 0.15)
	fondo_st.custom_minimum_size = Vector2(90, 10)
	col_stamina.add_child(fondo_st)
	_barra_stamina = fondo_st
	_relleno_stamina = ColorRect.new()
	_relleno_stamina.color = Color(0.3, 0.9, 0.3)
	_relleno_stamina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barra_stamina.add_child(_relleno_stamina)

	var ayuda := _etiqueta("1 Linterna · 2 Pistola · R Radar\nClic: disparar · ESC: pausa", 12, Color(0.7, 0.7, 0.7))
	ayuda.custom_minimum_size = Vector2(250, 0)
	fila.add_child(ayuda)


func _crear_slot(tipo: int) -> PanelContainer:
	var p := PanelContainer.new()
	var icono: Texture2D = Perks.icono(tipo)
	p.custom_minimum_size = Vector2(176 if icono != null else 130, 0)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.15, 0.15, 0.15)
	estilo.border_color = Color(0.3, 0.3, 0.3)
	estilo.set_border_width_all(3)
	estilo.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", estilo)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var img: TextureRect = null
	if icono != null:
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 8)
		p.add_child(fila)
		img = TextureRect.new()
		img.texture = icono
		img.custom_minimum_size = Vector2(46, 46)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fila.add_child(img)
		fila.add_child(v)
	else:
		p.add_child(v)
	v.add_child(_etiqueta(Perks.nombre(tipo).to_upper(), 14, Perks.color(tipo)))
	var valor := _etiqueta("—", 20, Color.WHITE)
	v.add_child(valor)
	_slots[tipo] = {"estilo": estilo, "valor": valor, "icono": img}
	return p


func _crear_radar() -> void:
	_radar = RadarHUD.new()
	_radar.visible = false
	_raiz.add_child(_radar)
	_radar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_radar.offset_left = -190.0
	_radar.offset_right = -20.0
	_radar.offset_top = 20.0
	_radar.offset_bottom = 190.0


func _crear_mira() -> void:
	# Cruz de mira centrada en pantalla (aparece solo con la pistola).
	# Alineada con el rayo de disparo que sale desde camara.global_position hacia -Z.
	_mira = Control.new()
	_mira.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mira.visible = false
	_raiz.add_child(_mira)
	_mira.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Línea horizontal
	var h := ColorRect.new()
	h.color = Color(1.0, 0.15, 0.1, 0.92)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_CENTER)
	h.offset_left = -10.0
	h.offset_right = 10.0
	h.offset_top = -1.5
	h.offset_bottom = 1.5
	_mira.add_child(h)

	# Línea vertical
	var v := ColorRect.new()
	v.color = Color(1.0, 0.15, 0.1, 0.92)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -1.5
	v.offset_right = 1.5
	v.offset_top = -10.0
	v.offset_bottom = 10.0
	_mira.add_child(v)


func _crear_mensaje() -> void:
	_lbl_mensaje = _etiqueta("", 26, Color(1.0, 0.9, 0.6))
	_raiz.add_child(_lbl_mensaje)
	_lbl_mensaje.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lbl_mensaje.offset_left = -300.0
	_lbl_mensaje.offset_right = 300.0
	_lbl_mensaje.offset_top = 40.0
	_lbl_mensaje.offset_bottom = 80.0
	_lbl_mensaje.modulate.a = 0.0


# ---------- Game-Over ----------

func _crear_pantalla_gameover() -> void:
	_pantalla_gameover = Control.new()
	_pantalla_gameover.mouse_filter = Control.MOUSE_FILTER_STOP
	_pantalla_gameover.visible = false
	_pantalla_gameover.modulate.a = 0.0
	add_child(_pantalla_gameover)   # fuera de _raiz para que quede encima de todo
	_pantalla_gameover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Fondo oscuro semitransparente
	var fondo := ColorRect.new()
	fondo.color = Color(0.0, 0.0, 0.0, 0.88)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pantalla_gameover.add_child(fondo)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Título GAME OVER
	var titulo := _etiqueta("GAME OVER", 92, Color(0.85, 0.06, 0.06))
	titulo.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	titulo.add_theme_constant_override("outline_size", 14)
	titulo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	titulo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pantalla_gameover.add_child(titulo)
	titulo.set_anchors_preset(Control.PRESET_CENTER)
	titulo.offset_left = -500.0
	titulo.offset_right = 500.0
	titulo.offset_top = -120.0
	titulo.offset_bottom = -20.0

	# Subtexto
	var sub := _etiqueta("Abaddon te alcanzó.\nPresiona R para reintentar o M para el menú", 28, Color(0.8, 0.75, 0.65))
	_pantalla_gameover.add_child(sub)
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.offset_left = -500.0
	sub.offset_right = 500.0
	sub.offset_top = 20.0
	sub.offset_bottom = 120.0


# ---------- Menú de Pausa ----------

func _crear_menu_pausa() -> void:
	_menu_pausa = Control.new()
	_menu_pausa.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_pausa.visible = false
	add_child(_menu_pausa)
	_menu_pausa.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Fondo
	var fondo := ColorRect.new()
	fondo.color = Color(0.05, 0.03, 0.03, 0.82)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_pausa.add_child(fondo)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Panel central
	var panel := PanelContainer.new()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.11, 0.08, 0.07)
	estilo.border_color = Color(0.55, 0.12, 0.10)
	estilo.set_border_width_all(4)
	estilo.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", estilo)
	_menu_pausa.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200.0
	panel.offset_right = 200.0
	panel.offset_top = -180.0
	panel.offset_bottom = 180.0

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	col.add_child(_etiqueta("PAUSADO", 48, Color(0.85, 0.06, 0.06)))
	col.add_child(_boton_pausa("CONTINUAR", _reanudar))
	col.add_child(_boton_pausa("REINICIAR", _reiniciar))
	col.add_child(_boton_pausa("MENÚ PRINCIPAL", _ir_menu))


func _boton_pausa(texto: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = texto
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.8))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.4, 0.3))
	var estilo_normal := StyleBoxFlat.new()
	estilo_normal.bg_color = Color(0.18, 0.12, 0.11)
	estilo_normal.border_color = Color(0.4, 0.10, 0.09)
	estilo_normal.set_border_width_all(2)
	estilo_normal.set_content_margin_all(10)
	var estilo_hover := StyleBoxFlat.new()
	estilo_hover.bg_color = Color(0.28, 0.10, 0.09)
	estilo_hover.border_color = Color(0.75, 0.15, 0.10)
	estilo_hover.set_border_width_all(2)
	estilo_hover.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", estilo_normal)
	btn.add_theme_stylebox_override("hover", estilo_hover)
	btn.add_theme_stylebox_override("pressed", estilo_hover)
	btn.pressed.connect(callback)
	return btn


func _reanudar() -> void:
	_pausado = false
	_menu_pausa.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _reiniciar() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()


func _ir_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(Partida.ESCENA_MENU)


func _abrir_pausa() -> void:
	if _gameover_visible:
		return
	_pausado = true
	_menu_pausa.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------- Lógica de pausa con ESC ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if _gameover_visible:
				return
			if _pausado:
				_reanudar()
			else:
				_abrir_pausa()
		elif _gameover_visible:
			if event.physical_keycode == KEY_R:
				_reiniciar()
			elif event.physical_keycode == KEY_M:
				_ir_menu()


# ---------- Actualización por frame ----------

func _process(delta: float) -> void:
	if jugador == null:
		return
	if _gameover_visible:
		# Fade-in de la pantalla de game-over
		if _gameover_alpha < 1.0:
			_gameover_alpha = minf(1.0, _gameover_alpha + delta * 0.8)
			_pantalla_gameover.modulate.a = _gameover_alpha
		return
	if jugador.esta_muerto:
		_actualizar_muerte(delta)
		# Mostrar game-over cuando la animación de caída termina
		if jugador._muerte_completada and not _gameover_visible:
			_gameover_visible = true
			_pantalla_gameover.visible = true
			_pantalla_gameover.modulate.a = 0.0
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	_actualizar_barra()
	_actualizar_stamina()
	_actualizar_mano(delta)
	_actualizar_efectos()
	_radar.visible = jugador.radar_activo
	_mira.visible = jugador.arma_actual == Jugador.Arma.PISTOLA
	if _mensaje_t > 0.0:
		_mensaje_t -= delta
		_lbl_mensaje.modulate.a = clampf(_mensaje_t, 0.0, 1.0)
	if _muzzle_t > 0.0:
		_muzzle_t -= delta
		_muzzle_flash.modulate.a = clampf(_muzzle_t / 0.06, 0.0, 1.0)
		if _muzzle_t <= 0.0:
			_muzzle_flash.visible = false


func _actualizar_barra() -> void:
	var con_pistola: bool = jugador.arma_actual == Jugador.Arma.PISTOLA
	_lbl_arma.text = "PISTOLA" if con_pistola else "LINTERNA"
	_set_slot(Perks.Tipo.PISTOLA, jugador.tiene_pistola, "%d bala%s" % [jugador.balas, "" if jugador.balas == 1 else "s"], con_pistola)
	var txt_radar: String = "%d s %s" % [ceili(jugador.radar_energia), "ON" if jugador.radar_activo else "OFF"]
	_set_slot(Perks.Tipo.RADAR, jugador.tiene_radar, txt_radar, jugador.radar_activo)
	_set_slot(Perks.Tipo.ESCUDO, jugador.tiene_escudo, "LISTO", jugador.tiene_escudo)


func _actualizar_stamina() -> void:
	if _relleno_stamina == null:
		return
	var ancho_max: float = _barra_stamina.size.x
	var fraccion: float = jugador.stamina / Jugador.STAMINA_MAX
	_relleno_stamina.size = Vector2(ancho_max * fraccion, _barra_stamina.size.y)
	_relleno_stamina.color = Color(0.3, 0.9, 0.3) if fraccion > 0.3 else Color(0.9, 0.5, 0.1)


func _set_slot(tipo: int, tiene: bool, texto: String, resaltado: bool) -> void:
	var s: Dictionary = _slots[tipo]
	var estilo: StyleBoxFlat = s["estilo"]
	var valor: Label = s["valor"]
	var color: Color = Perks.color(tipo)
	valor.text = texto if tiene else "—"
	var ic: TextureRect = s["icono"]
	if ic != null:
		ic.modulate = Color.WHITE if tiene else Color(0.3, 0.3, 0.3, 0.8)
	estilo.bg_color = color.darkened(0.7) if tiene else Color(0.15, 0.15, 0.15)
	if resaltado:
		estilo.border_color = color
	elif tiene:
		estilo.border_color = color.darkened(0.4)
	else:
		estilo.border_color = Color(0.3, 0.3, 0.3)


# ── Mano con arma ────────────────────────────────────────────────────────────
# La pistola se desplaza ligeramente a la derecha para que apunte hacia la mira central.
func _actualizar_mano(delta: float) -> void:
	var tex: Texture2D = _mano.texture
	if tex == null:
		return
	var vp: Vector2 = _raiz.size
	var es_pistola: bool = jugador.arma_actual == Jugador.Arma.PISTOLA
	var alto: float = vp.y * MANO_ALTO_RATIO
	var ancho: float = alto * tex.get_width() / float(tex.get_height())
	var vel: float = Vector2(jugador.velocity.x, jugador.velocity.z).length()
	var factor: float = clampf(vel / Jugador.VELOCIDAD_CAMINAR, 0.0, 1.6)
	_t_bob += delta * (4.0 + vel * 0.9)
	_retroceso = maxf(0.0, _retroceso - delta * 6.0)
	var bob_x: float = sin(_t_bob) * 14.0 * factor
	var bob_y: float = absf(cos(_t_bob)) * 10.0 * factor

	# Offset lateral: la pistola se desplaza a la derecha para alinear el cañón con la mira.
	var off_x: float = PISTOLA_OFFSET_X * vp.x if es_pistola else MANO_OFFSET_X * vp.x * 0.0
	var off_y_ratio: float = PISTOLA_OFFSET_Y if es_pistola else MANO_OFFSET_Y

	_mano.size = Vector2(ancho, alto)
	_mano.position = Vector2(
		(vp.x - ancho) / 2.0 + off_x + bob_x,
		vp.y - ALTO_BARRA - alto * off_y_ratio + bob_y + desliz * alto + _retroceso * 28.0)

	if _muzzle_flash.texture != null:
		var m_alto: float = alto * 0.35
		var m_ancho: float = m_alto * _muzzle_flash.texture.get_width() / float(_muzzle_flash.texture.get_height())
		_muzzle_flash.size = Vector2(m_ancho, m_alto)
		_muzzle_flash.position = Vector2(
			_mano.position.x + (ancho - m_ancho) / 2.0,
			_mano.position.y - m_alto * 0.80)


# ── Manos muertas ─────────────────────────────────────────────────────────────
func _actualizar_muerte(delta: float) -> void:
	if _mano_muerta.texture == null:
		return
	var vp: Vector2 = _raiz.size
	var alto: float = vp.y * MANO_ALTO_RATIO
	var ancho: float = alto * _mano_muerta.texture.get_width() / float(_mano_muerta.texture.get_height())
	_mano_muerta.size = Vector2(ancho, alto)
	var y_final: float = vp.y - ALTO_BARRA - alto * 0.60
	var y_actual: float = _mano_muerta.position.y
	_mano_muerta.position = Vector2(
		(vp.x - ancho) / 2.0,
		lerpf(y_actual, y_final, 3.5 * delta))


func _actualizar_textura() -> void:
	_mano.texture = _tex_linterna if jugador.arma_actual == Jugador.Arma.LINTERNA else _tex_pistola


func _mostrar(texto: String) -> void:
	_lbl_mensaje.text = texto
	_mensaje_t = 3.0
	_lbl_mensaje.modulate.a = 1.0


# ---------- Eventos del jugador ----------

func _on_perk_recogido(tipo: int) -> void:
	_mostrar("Recogiste: %s" % Perks.nombre(tipo).to_upper())


func _on_arma_cambiada(_arma: int) -> void:
	var tw := create_tween()
	tw.tween_property(self, "desliz", 1.0, 0.12)
	tw.tween_callback(_actualizar_textura)
	tw.tween_property(self, "desliz", 0.0, 0.18)


func _on_disparo() -> void:
	_retroceso = 1.0
	_flash.color.a = 0.3
	create_tween().tween_property(_flash, "color:a", 0.0, 0.08)
	if _muzzle_flash.texture != null:
		_muzzle_flash.visible = true
		_muzzle_flash.modulate.a = 1.0
		_muzzle_t = 0.06


func _on_escudo_roto() -> void:
	_mostrar("¡ESCUDO ROTO!")


func _on_jugador_muerto() -> void:
	_mano.visible = false
	_muzzle_flash.visible = false
	_mira.visible = false
	if _mano_muerta.texture != null:
		var vp: Vector2 = _raiz.size
		var alto: float = vp.y * MANO_ALTO_RATIO
		var ancho: float = alto * _mano_muerta.texture.get_width() / float(_mano_muerta.texture.get_height())
		_mano_muerta.size = Vector2(ancho, alto)
		_mano_muerta.position = Vector2(
			(vp.x - ancho) / 2.0,
			vp.y - ALTO_BARRA - alto * 1.20)
	_mano_muerta.visible = true


# ---------- Efectos de persecución ----------

func _material_shader(codigo: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = codigo
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _crear_efecto_rojo() -> void:
	_fx_rojo = ColorRect.new()
	_fx_rojo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_rojo.material = _material_shader(SHADER_ROJO)
	_fx_rojo.visible = false
	_raiz.add_child(_fx_rojo)
	_fx_rojo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pentagrama = MenuSigilo.new()
	_pentagrama.intensidad = 0.0
	_pentagrama.visible = false
	_raiz.add_child(_pentagrama)
	_pentagrama.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _crear_efecto_invertido() -> void:
	_fx_invertido = ColorRect.new()
	_fx_invertido.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_invertido.material = _material_shader(SHADER_INVERTIDO)
	_fx_invertido.visible = false
	_raiz.add_child(_fx_invertido)
	_fx_invertido.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lbl_huida = _etiqueta("", 72, Color(1.0, 0.95, 0.85))
	_lbl_huida.add_theme_color_override("font_outline_color", Color(0.7, 0.0, 0.05))
	_lbl_huida.add_theme_constant_override("outline_size", 14)
	_lbl_huida.visible = false
	_raiz.add_child(_lbl_huida)
	_lbl_huida.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_lbl_huida.offset_left = -350.0
	_lbl_huida.offset_right = 350.0
	_lbl_huida.offset_top = 100.0
	_lbl_huida.offset_bottom = 200.0


func _actualizar_efectos() -> void:
	var huyendo: bool = jugador.en_ventana_huida
	var k: float = 0.0 if huyendo else jugador.cercania
	var hay_rojo: bool = k > 0.01
	_fx_rojo.visible = hay_rojo
	_pentagrama.visible = hay_rojo
	if hay_rojo:
		(_fx_rojo.material as ShaderMaterial).set_shader_parameter("intensidad", k)
		_pentagrama.intensidad = pow(k, 1.3) * 1.7
	_fx_invertido.visible = huyendo
	_lbl_huida.visible = huyendo
	if huyendo:
		var t: float = jugador.tiempo_huida
		var fuerza: float = 1.0
		if t < 3.0 and fmod(t, 0.5) < 0.25:
			fuerza = 0.35
		(_fx_invertido.material as ShaderMaterial).set_shader_parameter("fuerza", fuerza)
		_lbl_huida.text = "¡HUYE!   %.1f" % t


func _mostrar_victoria() -> void:
	# Reutiliza la misma pantalla de game-over pero con texto de victoria.
	if _gameover_visible:
		return
	_gameover_visible = true
	# Cambiar textos si los nodos ya existen (los hijos 1 y 2 del panel son título y subtexto)
	for hijo in _pantalla_gameover.get_children():
		if hijo is Label:
			if hijo.text == "GAME OVER":
				hijo.text = "¡ESCAPASTE!"
				hijo.add_theme_color_override("font_color", Color(0.2, 0.85, 0.3))
			elif "Abaddon" in hijo.text:
				hijo.text = "Llegaste a la salida.\nVolviendo al menú..."
	_pantalla_gameover.visible = true
	_pantalla_gameover.modulate.a = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _etiqueta(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
