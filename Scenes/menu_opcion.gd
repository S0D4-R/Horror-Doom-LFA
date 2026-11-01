class_name MenuOpcion
extends Control
# Botón angular al estilo Persona/Atlus: paralelogramo inclinado.
# Normal: negro con borde rojo oscuro. Seleccionado: blanco hueso con sombra roja y texto negro.
# El estilo BANNER es un cartel rojo (títulos de pantalla) que no se puede pulsar.

signal elegida    # clic sobre la opción
signal enfocada   # el mouse entra en la opción

enum Estilo { OPCION, BANNER }

const SANGRE := Color(0.78, 0.04, 0.06)
const SANGRE_OSCURA := Color(0.38, 0.03, 0.04)
const HUESO := Color(0.94, 0.91, 0.84)
const NEGRO := Color(0.03, 0.02, 0.02)

var texto: String = ""
var fuente: Font
var tam_fuente: int = 34
var inclinacion: float = 26.0
var estilo: int = Estilo.OPCION
var _rot_base: float = -2.5

var seleccionada: bool = false:
	set(valor):
		if seleccionada == valor:
			return
		seleccionada = valor
		queue_redraw()
		var destino: float = -0.8 if valor else _rot_base   # al seleccionarla se endereza un poco
		create_tween().tween_property(self, "rotation_degrees", destino, 0.1)


func configurar(t: String, f: Font, tam: int, est: int, ancho: float, alto: float) -> void:
	texto = t
	fuente = f
	tam_fuente = tam
	estilo = est
	custom_minimum_size = Vector2(ancho, alto)
	pivot_offset = Vector2(0.0, alto * 0.5)
	_rot_base = -2.5 if est == Estilo.OPCION else -3.5
	rotation_degrees = _rot_base
	if est == Estilo.OPCION:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): enfocada.emit())
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _gui_input(event: InputEvent) -> void:
	if estilo == Estilo.OPCION and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		elegida.emit()


func _desplazar(forma: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var r := PackedVector2Array()
	for p in forma:
		r.append(p + d)
	return r


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var k: float = inclinacion
	var forma := PackedVector2Array([Vector2(k, 0.0), Vector2(w, 0.0), Vector2(w - k, h), Vector2(0.0, h)])
	var color_texto: Color = HUESO
	if estilo == Estilo.BANNER:
		draw_colored_polygon(_desplazar(forma, Vector2(7.0, 7.0)), NEGRO)
		draw_colored_polygon(forma, SANGRE)
	elif seleccionada:
		draw_colored_polygon(_desplazar(forma, Vector2(9.0, 9.0)), SANGRE)
		draw_colored_polygon(forma, HUESO)
		color_texto = NEGRO
	else:
		draw_colored_polygon(forma, Color(NEGRO, 0.88))
		var linea: PackedVector2Array = forma.duplicate()
		linea.append(forma[0])
		draw_polyline(linea, SANGRE_OSCURA, 2.0)
	if fuente != null:
		var asc: float = fuente.get_ascent(tam_fuente)
		var desc: float = fuente.get_descent(tam_fuente)
		var y: float = h * 0.5 + (asc - desc) * 0.5
		draw_string(fuente, Vector2(k + 20.0, y), texto, HORIZONTAL_ALIGNMENT_LEFT,
			w - k * 2.0 - 30.0, tam_fuente, color_texto)
