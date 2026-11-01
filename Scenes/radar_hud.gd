class_name RadarHUD
extends Control
# Radar circular: el jugador está al centro, mirando hacia arriba, y el punto rojo es el enemigo.

var jugador: Jugador
var objetivo: Node3D
var alcance: float = 30.0   # metros que cubre el radio del radar

const VERDE := Color(0.2, 1.0, 0.3)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var centro: Vector2 = size / 2.0
	var radio: float = minf(size.x, size.y) / 2.0 - 4.0
	draw_circle(centro, radio, Color(0.0, 0.08, 0.02, 0.75))
	draw_arc(centro, radio, 0.0, TAU, 48, VERDE, 2.0)
	draw_arc(centro, radio * 0.5, 0.0, TAU, 32, Color(VERDE, 0.4), 1.0)
	draw_line(centro, centro + Vector2(0.0, -radio), Color(VERDE, 0.5), 1.0)
	var t: float = Time.get_ticks_msec() / 1000.0
	draw_line(centro, centro + Vector2(cos(t * 2.0), sin(t * 2.0)) * radio, Color(VERDE, 0.35), 2.0)
	draw_circle(centro, 3.0, Color.WHITE)
	if jugador == null or objetivo == null:
		return
	# Posición del enemigo en los ejes del jugador: x = derecha, z = atrás (pantalla: abajo).
	var rel: Vector3 = objetivo.global_position - jugador.global_position
	var local: Vector3 = jugador.global_transform.basis.inverse() * rel
	var p: Vector2 = Vector2(local.x, local.z) / alcance * radio
	if p.length() > radio:
		p = p.normalized() * radio
	draw_circle(centro + p, 5.0, Color(1.0, 0.15, 0.1))
