class_name HUD
extends CanvasLayer
# HUD estilo Doom con menú de pausa (ESC), pantalla de GAME OVER, UI en esquinas y barra de estamina.

# TAMAÑOS DE SPRITE:
const MANO_ALTO_RATIO: float    = 0.68   
const MANO_OFFSET_X: float      = 0.12   
const MANO_OFFSET_Y: float      = 0.88   
const PISTOLA_OFFSET_X: float   = 0.08   
const PISTOLA_OFFSET_Y: float   = 0.92   

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
var _mira: Control          
var _flash: ColorRect
var _lbl_mensaje: Label
var _fx_rojo: ColorRect
var _pentagrama: MenuSigilo
var _fx_invertido: ColorRect
var _lbl_huida: Label

var _retroceso: float = 0.0
var _t_bob: float = 0.0
var _mensaje_t: float = 0.0
var _muzzle_t: float = 0.0

# Variables de la UI
var _ui_pistola: HBoxContainer
var _icono_pistola: TextureRect
var _lbl_municion: Label
var _icono_radar: TextureRect
var _icono_escudo: TextureRect
var _barra_estamina: ProgressBar
var _estilo_estamina: StyleBoxFlat

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
	_crear_ui_esquinas()
	_crear_barra_estamina()
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


func _crear_ui_esquinas() -> void:
	# --- ESQUINA INFERIOR IZQUIERDA (Pistola y Munición) ---
	_ui_pistola = HBoxContainer.new()
	_ui_pistola.add_theme_constant_override("separation", 10)
	_ui_pistola.alignment = BoxContainer.ALIGNMENT_CENTER
	_ui_pistola.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_ui_pistola)
	
	_ui_pistola.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_ui_pistola.offset_left = 30.0
	_ui_pistola.offset_right = 200.0
	_ui_pistola.offset_top = -110.0
	_ui_pistola.offset_bottom = -30.0
	_ui_pistola.visible = false 
	
	_icono_pistola = TextureRect.new()
	_icono_pistola.texture = Perks.icono(Perks.Tipo.PISTOLA)
	_icono_pistola.custom_minimum_size = Vector2(80, 80) 
	_icono_pistola.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icono_pistola.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ui_pistola.add_child(_icono_pistola)
	
	# Texto de munición con fuente tipo Times New Roman
	_lbl_municion = Label.new()
	_lbl_municion.text = "0"
	_lbl_municion.add_theme_font_size_override("font_size", 54)
	_lbl_municion.add_theme_color_override("font_color", Color.WHITE)
	
	var fuente_serif = SystemFont.new()
	fuente_serif.font_names = PackedStringArray(["Times New Roman", "Georgia", "serif"])
	_lbl_municion.add_theme_font_override("font", fuente_serif)
	
	_ui_pistola.add_child(_lbl_municion)

	# --- ESQUINA INFERIOR DERECHA (Radar y Escudo) ---
	var ui_derecha := HBoxContainer.new()
	ui_derecha.add_theme_constant_override("separation", 20)
	ui_derecha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(ui_derecha)
	
	ui_derecha.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ui_derecha.offset_left = -190.0   
	ui_derecha.offset_right = -30.0   
	ui_derecha.offset_top = -100.0    
	ui_derecha.offset_bottom = -30.0  
	
	_icono_radar = TextureRect.new()
	_icono_radar.texture = Perks.icono(Perks.Tipo.RADAR)
	_icono_radar.custom_minimum_size = Vector2(70, 70)
	_icono_radar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icono_radar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icono_radar.modulate = Color(0.2, 0.2, 0.2, 0.8)
	ui_derecha.add_child(_icono_radar)
	
	_icono_escudo = TextureRect.new()
	_icono_escudo.texture = Perks.icono(Perks.Tipo.ESCUDO)
	_icono_escudo.custom_minimum_size = Vector2(70, 70)
	_icono_escudo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icono_escudo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icono_escudo.modulate = Color(0.2, 0.2, 0.2, 0.8)
	ui_derecha.add_child(_icono_escudo)


func _crear_barra_estamina() -> void:
	_barra_estamina = ProgressBar.new()
	_barra_estamina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barra_estamina.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP 
	_barra_estamina.show_percentage = false 
	
	# Ajustamos al valor de tu script Jugador
	_barra_estamina.min_value = 0.0
	_barra_estamina.max_value = 5.0 
	_barra_estamina.value = 5.0 
	
	_raiz.add_child(_barra_estamina)
	
	_barra_estamina.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_barra_estamina.offset_left = 30.0
	_barra_estamina.offset_right = 45.0  
	_barra_estamina.offset_top = 30.0
	_barra_estamina.offset_bottom = 200.0 
	
	var estilo_fondo := StyleBoxFlat.new()
	estilo_fondo.bg_color = Color(0.1, 0.1, 0.1, 0.6) 
	_barra_estamina.add_theme_stylebox_override("background", estilo_fondo)
	
	_estilo_estamina = StyleBoxFlat.new()
	_estilo_estamina.bg_color = Color(0.15, 0.85, 0.25) 
	_barra_estamina.add_theme_stylebox_override("fill", _estilo_estamina)


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
	_mira = Control.new()
	_mira.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mira.visible = false
	_raiz.add_child(_mira)
	_mira.set_anchors_preset(Control.PRESET_FULL_RECT)

	var h := ColorRect.new()
	h.color = Color(1.0, 0.15, 0.1, 0.92)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_CENTER)
	h.offset_left = -10.0
	h.offset_right = 10.0
	h.offset_top = -1.5
	h.offset_bottom = 1.5
	_mira.add_child(h)

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
	add_child(_pantalla_gameover)
	_pantalla_gameover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var fondo := ColorRect.new()
	fondo.color = Color(0.0, 0.0, 0.0, 0.88)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pantalla_gameover.add_child(fondo)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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

	var fondo := ColorRect.new()
	fondo.color = Color(0.05, 0.03, 0.03, 0.82)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_pausa.add_child(fondo)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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
		if _gameover_alpha < 1.0:
			_gameover_alpha = minf(1.0, _gameover_alpha + delta * 0.8)
			_pantalla_gameover.modulate.a = _gameover_alpha
		return
	if jugador.esta_muerto:
		_actualizar_muerte(delta)
		if jugador._muerte_completada and not _gameover_visible:
			_gameover_visible = true
			_pantalla_gameover.visible = true
			_pantalla_gameover.modulate.a = 0.0
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
		
	_actualizar_ui()
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


func _actualizar_ui() -> void:
	_ui_pistola.visible = jugador.tiene_pistola
	if jugador.tiene_pistola:
		_lbl_municion.text = "%d" % jugador.balas 
	
	_icono_radar.modulate = Color.WHITE if jugador.tiene_radar else Color(0.2, 0.2, 0.2, 0.8)
	_icono_escudo.modulate = Color.WHITE if jugador.tiene_escudo else Color(0.2, 0.2, 0.2, 0.8)
	
	# Leemos la variable exacta que definiste en el script Jugador
	if "stamina" in jugador:
		var valor: float = jugador.stamina
		var max_stamina: float = jugador.STAMINA_MAX #[cite: 13]
		var porcentaje: float = valor / max_stamina
		
		_barra_estamina.value = valor
		
		# 1. Color dinámico (Rojo cuando está vacía, Verde cuando está llena)
		var color_verde := Color(0.15, 0.85, 0.25)
		var color_rojo := Color(0.85, 0.12, 0.10)
		_estilo_estamina.bg_color = color_rojo.lerp(color_verde, porcentaje)
		
		# 2. Auto-ocultar cuando está llena (suavizado)
		if valor >= max_stamina - 0.05:
			_barra_estamina.modulate.a = lerpf(_barra_estamina.modulate.a, 0.0, 0.1)
		else:
			_barra_estamina.modulate.a = lerpf(_barra_estamina.modulate.a, 1.0, 0.25)
			
		# 3. Parpadeo de alerta si se queda sin estamina (cerca de 0)
		if valor < 0.1:
			_barra_estamina.modulate.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.015)


# ── Mano con arma ────────────────────────────────────────────────────────────
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

	var off_x: float = PISTOLA_OFFSET_X * vp.x if es_pistola else MANO_OFFSET_X * vp.x * 0.0
	var off_y_ratio: float = PISTOLA_OFFSET_Y if es_pistola else MANO_OFFSET_Y

	_mano.size = Vector2(ancho, alto)
	_mano.position = Vector2(
		(vp.x - ancho) / 2.0 + off_x + bob_x,
		vp.y - alto * off_y_ratio + bob_y + desliz * alto + _retroceso * 28.0)

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
	var y_final: float = vp.y - alto * 0.60
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
			vp.y - alto * 1.20)
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
	if _gameover_visible:
		return
	_gameover_visible = true
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
