class_name MenuSigilo
extends Control
# Círculo ritual con pentagrama invertido que gira muy despacio detrás del menú,
# y gotas de sangre que cuelgan del título (cuando el menú le pasa su rectángulo).

const SANGRE := Color(0.80, 0.06, 0.08)
const SANGRE_SECA := Color(0.55, 0.02, 0.03)

var intensidad: float = 1.0           # 0 = invisible, 1 = máxima (sin guion bajo: se anima con tweens)
var rect_goteo: Rect2 = Rect2()       # rectángulo del título en pantalla; vacío = sin gotas

var _t: float = 0.0
var _gotas: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	for i in 7:
		_gotas.append(_nueva_gota())


func _nueva_gota() -> Dictionary:
	return {
		"x": randf(),
		"largo": 0.0,
		"max": randf_range(30.0, 120.0),
		"vel": randf_range(12.0, 38.0),
		"ancho": randf_range(2.0, 4.5),
		"espera": randf_range(0.5, 5.0),
	}


func _process(delta: float) -> void:
	_t += delta
	for g in _gotas:
		if g["espera"] > 0.0:
			g["espera"] -= delta
		else:
			g["largo"] += g["vel"] * delta
			if g["largo"] >= g["max"]:
				g.merge(_nueva_gota(), true)   # reinicia la gota con valores nuevos
	queue_redraw()


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.44
	var col := Color(SANGRE, 0.5 * intensidad)
	if intensidad > 0.01:
		draw_set_transform(Vector2(size.x * 0.5, size.y * 0.45), _t * 0.04, Vector2.ONE)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, col, 3.0, true)
		draw_arc(Vector2.ZERO, r * 0.94, 0.0, TAU, 96, col, 1.5, true)
		draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 64, Color(col, col.a * 0.6), 1.5, true)
		for i in 48:   # marcas alrededor del círculo, como un reloj ritual
			var a: float = i * TAU / 48.0
			var largo: float = 0.06 if i % 4 == 0 else 0.03
			draw_line(Vector2(cos(a), sin(a)) * r * 0.94, Vector2(cos(a), sin(a)) * r * (0.94 - largo), col, 1.5)
		var v: Array[Vector2] = []
		for i in 5:   # pentagrama invertido: un vértice apunta hacia abajo
			var a: float = PI * 0.5 + i * TAU / 5.0
			v.append(Vector2(cos(a), sin(a)) * r * 0.94)
		draw_polyline(PackedVector2Array([v[0], v[2], v[4], v[1], v[3], v[0]]), col, 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if rect_goteo.size.x > 0.0:   # gotas de sangre bajo las letras del título
		for g in _gotas:
			if g["espera"] > 0.0 or g["largo"] <= 0.0:
				continue
			var x: float = rect_goteo.position.x + g["x"] * rect_goteo.size.x
			var y: float = rect_goteo.end.y - rect_goteo.size.y * 0.30
			draw_rect(Rect2(x, y, g["ancho"], g["largo"]), SANGRE_SECA)
			draw_circle(Vector2(x + g["ancho"] / 2.0, y + g["largo"]), g["ancho"] * 0.9, SANGRE_SECA)
