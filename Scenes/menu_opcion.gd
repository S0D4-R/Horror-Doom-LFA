class_name MenuOpcion
extends Control
# Opción de menú de terror (al estilo The Wolf Among Us, pero demoníaco): sin cajas, solo texto gótico.
# Normal: rojo sangre. Seleccionada: blanco hueso, más grande, con aura roja, temblor, fallos de
# imagen ocasionales y un pentagrama invertido a su lado.
# BANNER: título de pantalla en rojo, con subrayado irregular y gotas de sangre que cuelgan.

signal elegida    # clic sobre la opción
signal enfocada   # el mouse entra en la opción

enum Estilo { OPCION, BANNER }

const SANGRE := Color(0.80, 0.06, 0.08)
const HUESO := Color(0.97, 0.92, 0.80)
const NEGRO := Color(0.02, 0.0, 0.0)

var texto: String = ""
var fuente: Font
var tam_fuente: int = 44
var estilo: int = Estilo.OPCION

var _t: float = 0.0
var _glitch: float = 0.0
var _gotas: Array = []

var seleccionada: bool = false:
	set(valor):
		if seleccionada == valor:
			return
		seleccionada = valor
		queue_redraw()


func configurar(t: String, f: Font, tam: int, est: int, ancho: float, alto: float) -> void:
	texto = t
	fuente = f
	tam_fuente = tam
	estilo = est
	custom_minimum_size = Vector2(ancho, alto)
	var rng := RandomNumberGenerator.new()
	rng.seed = t.hash()
	_t = rng.randf() * 10.0
	if est == Estilo.OPCION:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): enfocada.emit())
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 6:
			_gotas.append({
				"x": rng.randf_range(0.04, 0.9),
				"largo": rng.randf_range(10.0, 22.0),
				"fase": rng.randf() * TAU,
				"ancho": rng.randf_range(2.0, 3.5),
			})


func _gui_input(event: InputEvent) -> void:
	if estilo == Estilo.OPCION and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		elegida.emit()


func _process(delta: float) -> void:
	_t += delta
	if seleccionada:
		_glitch = maxf(0.0, _glitch - delta)
		if _glitch <= 0.0 and randf() < 0.012:
			_glitch = randf_range(0.05, 0.14)
		queue_redraw()
	elif estilo == Estilo.BANNER:
		queue_redraw()


func _draw() -> void:
	if fuente == null:
		return
	if estilo == Estilo.BANNER:
		_dibujar_banner()
	else:
		_dibujar_opcion()


func _base_y(tam: int) -> float:
	return size.y * 0.5 + (fuente.get_ascent(tam) - fuente.get_descent(tam)) * 0.5


func _dibujar_opcion() -> void:
	var h: float = size.y
	var x0: float = h   # espacio reservado a la izquierda para el pentagrama
	var tam: int = int(tam_fuente * 1.1) if seleccionada else tam_fuente
	var pos := Vector2(x0, _base_y(tam))
	var ancho: float = size.x - x0
	if seleccionada:
		pos += Vector2(sin(_t * 47.0), cos(_t * 41.0)) * 0.7   # temblor
		for k in 8:   # aura roja
			var a: float = k * TAU / 8.0
			draw_string(fuente, pos + Vector2(cos(a), sin(a)) * 4.0, texto,
				HORIZONTAL_ALIGNMENT_LEFT, ancho, tam, Color(SANGRE, 0.30))
		if _glitch > 0.0:   # copia desplazada, como un fallo de imagen
			draw_string(fuente, pos + Vector2(randf_range(-10.0, 10.0), randf_range(-3.0, 3.0)), texto,
				HORIZONTAL_ALIGNMENT_LEFT, ancho, tam, Color(SANGRE, 0.75))
		_pentagrama(Vector2(h * 0.48, h * 0.52), h * 0.30)
	draw_string_outline(fuente, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, ancho, tam, 8, NEGRO)
	draw_string(fuente, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, ancho, tam, HUESO if seleccionada else SANGRE)


# Pentagrama invertido (un vértice apunta hacia abajo) dentro de un círculo, con resplandor.
func _pentagrama(c: Vector2, r: float) -> void:
	var giro: float = sin(_t * 1.6) * 0.15
	var v: Array[Vector2] = []
	for i in 5:
		var a: float = PI * 0.5 + giro + i * TAU / 5.0
		v.append(c + Vector2(cos(a), sin(a)) * r)
	var estrella := PackedVector2Array([v[0], v[2], v[4], v[1], v[3], v[0]])
	draw_arc(c, r * 1.22, 0.0, TAU, 32, Color(SANGRE, 0.35), 5.0, true)
	draw_polyline(estrella, Color(SANGRE, 0.35), 6.0, true)
	draw_arc(c, r * 1.22, 0.0, TAU, 32, SANGRE, 2.0, true)
	draw_polyline(estrella, SANGRE, 2.0, true)


func _dibujar_banner() -> void:
	var pos := Vector2(0.0, _base_y(tam_fuente) - 6.0)
	draw_string_outline(fuente, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, size.x, tam_fuente, 10, NEGRO)
	draw_string(fuente, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, size.x, tam_fuente, SANGRE)
	var ancho_t: float = fuente.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam_fuente).x
	var y_l: float = size.y - 8.0
	var linea := PackedVector2Array()   # subrayado irregular, como trazado a mano
	var n: int = 14
	for i in n + 1:
		var x: float = ancho_t * 1.05 * i / n
		linea.append(Vector2(x, y_l + sin(i * 2.7) * 2.0 + (1.5 if i % 2 == 0 else -1.5)))
	draw_polyline(linea, SANGRE, 3.0, true)
	for g in _gotas:   # gotas que crecen y se encogen despacio
		var gx: float = ancho_t * g["x"]
		var largo: float = g["largo"] * (0.6 + 0.4 * sin(_t * 0.7 + g["fase"]))
		draw_line(Vector2(gx, y_l), Vector2(gx, y_l + largo), SANGRE, g["ancho"])
		draw_circle(Vector2(gx, y_l + largo), g["ancho"] * 1.2, SANGRE)
