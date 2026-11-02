class_name HUD
extends CanvasLayer
# HUD estilo Doom: mano con arma al centro, barra de estado abajo, radar arriba a la derecha.
# Se construye por código; solo necesita llamar a conectar(jugador, enemigo).

const ALTO_BARRA: float = 84.0
const COLOR_FONDO := Color(0.14, 0.11, 0.10)
const COLOR_BORDE := Color(0.45, 0.12, 0.10)
const COLOR_ROJO := Color(0.85, 0.12, 0.10)
const PERKS: Array = [Perks.Tipo.PISTOLA, Perks.Tipo.RADAR, Perks.Tipo.ESCUDO]

# Cerca del enemigo: la imagen se vuelve rojiza (más en los bordes) y late más rápido mientras más cerca.
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

# Tras gastar el escudo: colores invertidos durante la ventana de huida.
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
var desliz: float = 0.0   # 0 = arma arriba, 1 = arma bajada (animación de cambio de arma)

var _raiz: Control
var _mano: TextureRect
var _tex_linterna: Texture2D
var _tex_pistola: Texture2D
var _radar: RadarHUD
var _mira: ColorRect
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


func _ready() -> void:
	_tex_linterna = load("res://Assets/Chars/hand.png")
	_tex_pistola = load("res://Assets/Chars/pistol.png")
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raiz)
	_raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crear_efecto_rojo()
	_crear_mano()
	_crear_flash()
	_crear_barra()
	_crear_radar()
	_crear_mira()
	_crear_mensaje()
	_crear_efecto_invertido()


func conectar(j: Jugador, e: Node3D) -> void:
	jugador = j
	enemigo = e
	_radar.jugador = j
	_radar.objetivo = e
	j.perk_recogido.connect(_on_perk_recogido)
	j.arma_cambiada.connect(_on_arma_cambiada)
	j.disparo_realizado.connect(_on_disparo)
	j.escudo_roto.connect(_on_escudo_roto)
	_actualizar_textura()


# ---------- Construcción ----------

func _crear_mano() -> void:
	_mano = TextureRect.new()
	_mano.texture = _tex_linterna
	_mano.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # píxeles nítidos
	_mano.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mano.stretch_mode = TextureRect.STRETCH_SCALE
	_mano.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_mano)


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
	var ayuda := _etiqueta("1 Linterna · 2 Pistola · R Radar\nClic: disparar · M: menú", 12, Color(0.7, 0.7, 0.7))
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
	if icono != null:   # ícono a la izquierda y, a su derecha, el nombre y el valor
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
	_mira = ColorRect.new()
	_mira.color = Color(1.0, 0.2, 0.1, 0.9)
	_mira.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_mira)
	_mira.set_anchors_preset(Control.PRESET_CENTER)
	_mira.offset_left = -2.0
	_mira.offset_right = 2.0
	_mira.offset_top = -2.0
	_mira.offset_bottom = 2.0
	_mira.visible = false


func _crear_mensaje() -> void:
	_lbl_mensaje = _etiqueta("", 26, Color(1.0, 0.9, 0.6))
	_raiz.add_child(_lbl_mensaje)
	_lbl_mensaje.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lbl_mensaje.offset_left = -300.0
	_lbl_mensaje.offset_right = 300.0
	_lbl_mensaje.offset_top = 40.0
	_lbl_mensaje.offset_bottom = 80.0
	_lbl_mensaje.modulate.a = 0.0


func _etiqueta(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------- Actualización por frame ----------

func _process(delta: float) -> void:
	if jugador == null:
		return
	_actualizar_barra()
	_actualizar_mano(delta)
	_actualizar_efectos()
	_radar.visible = jugador.radar_activo
	_mira.visible = jugador.arma_actual == Jugador.Arma.PISTOLA
	if _mensaje_t > 0.0:
		_mensaje_t -= delta
		_lbl_mensaje.modulate.a = clampf(_mensaje_t, 0.0, 1.0)


func _actualizar_barra() -> void:
	var con_pistola: bool = jugador.arma_actual == Jugador.Arma.PISTOLA
	_lbl_arma.text = "PISTOLA" if con_pistola else "LINTERNA"
	_set_slot(Perks.Tipo.PISTOLA, jugador.tiene_pistola, "%d balas" % jugador.balas, con_pistola)
	var txt_radar: String = "%d s %s" % [ceili(jugador.radar_energia), "ON" if jugador.radar_activo else "OFF"]
	_set_slot(Perks.Tipo.RADAR, jugador.tiene_radar, txt_radar, jugador.radar_activo)
	_set_slot(Perks.Tipo.ESCUDO, jugador.tiene_escudo, "LISTO", jugador.tiene_escudo)


func _set_slot(tipo: int, tiene: bool, texto: String, resaltado: bool) -> void:
	var s: Dictionary = _slots[tipo]
	var estilo: StyleBoxFlat = s["estilo"]
	var valor: Label = s["valor"]
	var color: Color = Perks.color(tipo)
	valor.text = texto if tiene else "—"
	var ic: TextureRect = s["icono"]   # el ícono se oscurece mientras no tienes el perk
	if ic != null:
		ic.modulate = Color.WHITE if tiene else Color(0.3, 0.3, 0.3, 0.8)
	estilo.bg_color = color.darkened(0.7) if tiene else Color(0.15, 0.15, 0.15)
	if resaltado:
		estilo.border_color = color
	elif tiene:
		estilo.border_color = color.darkened(0.4)
	else:
		estilo.border_color = Color(0.3, 0.3, 0.3)


# La mano se mueve al caminar (bobbing), retrocede al disparar y baja al cambiar de arma.
func _actualizar_mano(delta: float) -> void:
	var tex: Texture2D = _mano.texture
	if tex == null:
		return
	var vp: Vector2 = _raiz.size
	var alto: float = vp.y * 0.55
	var ancho: float = alto * tex.get_width() / float(tex.get_height())
	var vel: float = Vector2(jugador.velocity.x, jugador.velocity.z).length()
	var factor: float = clampf(vel / jugador.velocidad, 0.0, 1.6)
	_t_bob += delta * (4.0 + vel * 0.9)
	_retroceso = maxf(0.0, _retroceso - delta * 6.0)
	var bob_x: float = sin(_t_bob) * 14.0 * factor
	var bob_y: float = absf(cos(_t_bob)) * 10.0 * factor
	_mano.size = Vector2(ancho, alto)
	_mano.position = Vector2(
		(vp.x - ancho) / 2.0 + vp.x * 0.10 + bob_x,
		vp.y - ALTO_BARRA - alto * 0.88 + bob_y + desliz * alto + _retroceso * 28.0)


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


func _on_escudo_roto() -> void:
	_mostrar("¡ESCUDO ROTO!")


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
	_pentagrama = MenuSigilo.new()   # el mismo círculo ritual del menú, aquí a pantalla completa
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
	_lbl_huida = _etiqueta("", 72, Color(1.0, 0.95, 0.85))   # contador de la ventana de huida
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
	# Durante la huida el rojo se apaga: solo quedan los colores invertidos y el reloj.
	var k: float = 0.0 if huyendo else jugador.cercania
	var hay_rojo: bool = k > 0.01
	_fx_rojo.visible = hay_rojo
	_pentagrama.visible = hay_rojo
	if hay_rojo:
		(_fx_rojo.material as ShaderMaterial).set_shader_parameter("intensidad", k)
		_pentagrama.intensidad = pow(k, 1.3) * 1.7   # más opaco mientras más cerca (hasta ~85 %)
	_fx_invertido.visible = huyendo
	_lbl_huida.visible = huyendo
	if huyendo:
		var t: float = jugador.tiempo_huida
		var fuerza: float = 1.0
		if t < 3.0 and fmod(t, 0.5) < 0.25:   # parpadea en los últimos 3 s para avisar
			fuerza = 0.35
		(_fx_invertido.material as ShaderMaterial).set_shader_parameter("fuerza", fuerza)
		_lbl_huida.text = "¡HUYE!   %.1f" % t
