class_name Jugador
extends CharacterBody3D
# Jugador en primera persona. Se construye solo: cuerpo, colisión, cámara y linterna.
# Controles: WASD / flechas = mover, A/D = deslizarse, flechas izq/der = girar, mouse = mirar,
# Shift = correr, 1 = linterna, 2 = pistola, R = radar, clic izquierdo = disparar, Esc = soltar mouse.

signal celda_cambiada(celda: Vector2i)    # entra a una celda nueva (cuenta como un paso)
signal perk_recogido(tipo: int)
signal arma_cambiada(arma: int)
signal disparo_realizado
signal escudo_roto

enum Arma { LINTERNA, PISTOLA }

# --- Ajustes de la linterna (bájalos o súbelos a gusto) ---
const LINTERNA_ENERGIA: float = 1.8
const LINTERNA_ALCANCE: float = 14.0
const LINTERNA_ANGULO: float = 30.0
const LINTERNA_CON_PISTOLA: float = 0.4    # fracción de luz cuando llevas la pistola en la mano

# --- Ajustes de los perks ---
const BALAS_POR_PISTOLA: int = 6
const CADENCIA: float = 0.45               # segundos entre disparos
const RADAR_DURACION: float = 20.0         # segundos de radar por perk

@export var velocidad: float = 5.0
@export var sensibilidad: float = 0.0025
@export var velocidad_giro: float = 2.2
@export var gravedad: float = 20.0
@export var altura_ojos: float = 1.6

var tam_celda: float = 2.0
var celda_actual: Vector2i = Vector2i(-1, -1)
var camara: Camera3D
var linterna: SpotLight3D

# Inventario: estos valores también forman parte del estado del autómata.
var arma_actual: int = Arma.LINTERNA
var tiene_pistola: bool = false
var balas: int = 0
var tiene_radar: bool = false
var radar_activo: bool = false
var radar_energia: float = 0.0
var tiene_escudo: bool = false

var _pitch: float = 0.0
var _enfriamiento: float = 0.0
var _flash: OmniLight3D


func _ready() -> void:
	var col := CollisionShape3D.new()
	var capsula := CapsuleShape3D.new()
	capsula.radius = 0.35
	capsula.height = 1.8
	col.shape = capsula
	col.position.y = 0.9
	add_child(col)

	camara = Camera3D.new()
	camara.position.y = altura_ojos
	camara.fov = 75.0
	camara.near = 0.05
	add_child(camara)
	camara.current = true

	linterna = SpotLight3D.new()
	linterna.spot_range = LINTERNA_ALCANCE
	linterna.spot_angle = LINTERNA_ANGULO
	linterna.shadow_enabled = true
	camara.add_child(linterna)
	_actualizar_linterna()

	_flash = OmniLight3D.new()    # destello del disparo
	_flash.light_color = Color(1.0, 0.8, 0.4)
	_flash.omni_range = 8.0
	_flash.light_energy = 0.0
	camara.add_child(_flash)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensibilidad)
		_pitch = clampf(_pitch - event.relative.y * sensibilidad, -1.2, 1.2)
		camara.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			disparar()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				equipar(Arma.LINTERNA)
			KEY_2:
				equipar(Arma.PISTOLA)
			KEY_R:
				alternar_radar()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	var giro: int = int(Input.is_physical_key_pressed(KEY_LEFT)) - int(Input.is_physical_key_pressed(KEY_RIGHT))
	rotate_y(giro * velocidad_giro * delta)

	var lateral: int = int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
	var frontal: int = int(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) \
		- int(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var dir: Vector3 = (global_transform.basis * Vector3(lateral, 0.0, frontal)).normalized()
	var v: float = velocidad * (1.6 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	velocity.x = dir.x * v
	velocity.z = dir.z * v
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravedad * delta
	move_and_slide()

	_enfriamiento = maxf(0.0, _enfriamiento - delta)
	if radar_activo:
		radar_energia -= delta
		if radar_energia <= 0.0:    # se agota la batería: se pierde el perk
			radar_energia = 0.0
			radar_activo = false
			tiene_radar = false

	var c := Vector2i(floori(global_position.x / tam_celda), floori(global_position.z / tam_celda))
	if c != celda_actual:
		celda_actual = c
		celda_cambiada.emit(c)
		
		# --- NOTIFICAR AL AUTÓMATA DEL ENEMIGO ---
		# Busca el nodo del enemigo en la escena (ajusta la ruta si es necesario)
		var enemigo = get_node_or_null("../EnemigoPerseguidor")
		if enemigo and enemigo.has_method("registrar_movimiento_jugador"):
			enemigo.registrar_movimiento_jugador()


# ---------- Perks ----------

func recoger_perk(tipo: int) -> void:
	if tipo == Perks.Tipo.PISTOLA:
		tiene_pistola = true
		balas += BALAS_POR_PISTOLA
		equipar(Arma.PISTOLA)
	elif tipo == Perks.Tipo.RADAR:
		tiene_radar = true
		radar_energia = RADAR_DURACION
		radar_activo = true
	elif tipo == Perks.Tipo.ESCUDO:
		tiene_escudo = true
	perk_recogido.emit(tipo)


func equipar(a: int) -> void:
	if a == Arma.PISTOLA and not tiene_pistola:
		return
	if a == arma_actual:
		return
	arma_actual = a
	_actualizar_linterna()
	arma_cambiada.emit(a)


func alternar_radar() -> void:
	if tiene_radar:
		radar_activo = not radar_activo


func disparar() -> void:
	if arma_actual != Arma.PISTOLA or balas <= 0 or _enfriamiento > 0.0:
		return
	balas -= 1
	_enfriamiento = CADENCIA
	disparo_realizado.emit()
	_destello()
	var origen: Vector3 = camara.global_position
	var destino: Vector3 = origen - camara.global_transform.basis.z * 40.0
	var excluir: Array[RID] = [get_rid()]
	var consulta := PhysicsRayQueryParameters3D.create(origen, destino, 1, excluir)
	var impacto: Dictionary = get_world_3d().direct_space_state.intersect_ray(consulta)
	if not impacto.is_empty() and impacto["collider"].has_method("recibir_disparo"):
		impacto["collider"].recibir_disparo()    # el enemigo implementará este método


# El enemigo llama a esto al alcanzarte. Devuelve true si el ataque es letal.
func recibir_ataque() -> bool:
	if tiene_escudo:
		tiene_escudo = false
		escudo_roto.emit()
		return false
	return true


func _actualizar_linterna() -> void:
	var f: float = 1.0 if arma_actual == Arma.LINTERNA else LINTERNA_CON_PISTOLA
	linterna.light_energy = LINTERNA_ENERGIA * f


func _destello() -> void:
	_flash.light_energy = 6.0
	create_tween().tween_property(_flash, "light_energy", 0.0, 0.1)
