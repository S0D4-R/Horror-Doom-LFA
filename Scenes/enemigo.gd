class_name Perseguidor
extends CharacterBody3D
# Perseguidor. Usa Dijkstra (Grafo.dijkstra) para hallar el camino más corto hacia la celda
# actual del jugador. Si recibe un disparo se aturde de 2 a 4 s y luego vuelve a la caza.
 
signal alcanzo_jugador   # tocó al jugador y el ataque fue letal
signal aturdido
signal recuperado
 
@export var velocidad: float = 3.5
@export var gravedad: float = 20.0
@export var recalculo: float = 0.25        # cada cuántos segundos recalcula la ruta
@export var distancia_ataque: float = 1.1
@export var aturdimiento_min: float = 2.0
@export var aturdimiento_max: float = 4.0
 
var mapa: Mapa3D
var jugador: Jugador
var ruta: Array[Vector2i] = []
var esta_aturdido: bool = false
 
var _t_recalculo: float = 0.0
var _t_aturdido: float = 0.0
var _t_ataque: float = 0.0
var _mat: StandardMaterial3D
var _luz: OmniLight3D
var _color_normal: Color = Color(1.0, 0.1, 0.1)
var _color_aturdido: Color = Color(1.0, 0.9, 0.1)
 
 
func _ready() -> void:
	var col := CollisionShape3D.new()
	var capsula := CapsuleShape3D.new()
	capsula.radius = 0.4
	capsula.height = 1.8
	col.shape = capsula
	col.position.y = 0.9
	add_child(col)
 
	var malla := MeshInstance3D.new()
	var forma := CapsuleMesh.new()
	forma.radius = 0.4
	forma.height = 1.8
	malla.mesh = forma
	malla.position.y = 0.9
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	malla.material_override = _mat
	add_child(malla)
 
	_luz = OmniLight3D.new()
	_luz.omni_range = 4.0
	_luz.position.y = 1.2
	add_child(_luz)
	_pintar(_color_normal)
 
 
func _physics_process(delta: float) -> void:
	if mapa == null or jugador == null:
		return
	_t_ataque = maxf(0.0, _t_ataque - delta)
 
	if esta_aturdido:
		_t_aturdido -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _t_aturdido <= 0.0:
			esta_aturdido = false
			_pintar(_color_normal)
			_t_recalculo = 0.0   # recalcular la ruta de inmediato
			recuperado.emit()
	else:
		_t_recalculo -= delta
		if _t_recalculo <= 0.0:
			_t_recalculo = recalculo
			_recalcular_ruta()
		_seguir_ruta()
		_intentar_atacar()
 
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravedad * delta
	move_and_slide()
 
 
func celda_actual() -> Vector2i:
	return Vector2i(floori(global_position.x / mapa.tam_celda), floori(global_position.z / mapa.tam_celda))
 
 
# Dijkstra desde mi celda hasta la celda del jugador.
func _recalcular_ruta() -> void:
	ruta = Grafo.dijkstra(mapa.matriz, celda_actual(), jugador.celda_actual)
 
 
func _seguir_ruta() -> void:
	# La posición 0 es mi propia celda; avanzo hacia la siguiente.
	var objetivo: Vector3
	if ruta.size() >= 2:
		objetivo = mapa.celda_a_mundo(ruta[1])
		# Ya en la celda del jugador (ruta corta): ir directo hacia él.
		if ruta.size() == 2 and ruta[1] == jugador.celda_actual:
			objetivo = jugador.global_position
	else:
		objetivo = jugador.global_position
	var dir: Vector3 = objetivo - global_position
	dir.y = 0.0
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity.x = dir.x * velocidad
		velocity.z = dir.z * velocidad
		look_at(global_position + Vector3(dir.x, 0.0, dir.z), Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
 
 
func _intentar_atacar() -> void:
	if _t_ataque > 0.0:
		return
	var d: Vector3 = jugador.global_position - global_position
	d.y = 0.0
	if d.length() <= distancia_ataque:
		_t_ataque = 1.5   # evita repetir el ataque cada frame (por si el escudo absorbe el golpe)
		if jugador.recibir_ataque():
			alcanzo_jugador.emit()
 
 
# Lo llama Jugador.disparar() cuando la bala le pega.
func recibir_disparo() -> void:
	esta_aturdido = true
	_t_aturdido = randf_range(aturdimiento_min, aturdimiento_max)
	_pintar(_color_aturdido)
	aturdido.emit()
 
 
func _pintar(c: Color) -> void:
	_mat.albedo_color = c
	_mat.emission = c
	_luz.light_color = c
	_luz.light_energy = 1.2
 
