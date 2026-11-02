class_name Jugador
extends CharacterBody3D
# Jugador en primera persona. Se construye solo: cuerpo, colisión, cámara, linterna y sonidos.
# Controles: WASD / flechas = mover, A/D = deslizarse, flechas izq/der = girar, mouse = mirar,
# Shift = correr, 1 = linterna, 2 = pistola, RUEDA DEL MOUSE = alternar linterna/pistola,
# R = radar, clic izquierdo = disparar, Esc = soltar mouse.

signal celda_cambiada(celda: Vector2i)    # entra a una celda nueva (cuenta como un paso)
signal perk_recogido(tipo: int)
signal arma_cambiada(arma: int)
signal disparo_realizado
signal escudo_roto
signal ventana_huida_iniciada
signal ventana_huida_terminada
signal linterna_cambiada(encendida: bool)

enum Arma { LINTERNA, PISTOLA }

# --- Ajustes de la linterna ---
const LINTERNA_ENERGIA: float = 1.8
const LINTERNA_ALCANCE: float = 14.0
const LINTERNA_ANGULO: float = 30.0
const LINTERNA_CON_PISTOLA: float = 0.4    # fracción de luz cuando llevas la pistola en la mano

# --- Ajustes de los perks ---
const BALAS_POR_PISTOLA: int = 6
const CADENCIA: float = 0.45               # segundos entre disparos
const RADAR_DURACION: float = 20.0         # segundos de radar por perk

# --- Persecución (solo en el modo U R D4MN3D) ---
const RADIO_CERCANIA: float = 16.0         # metros: a esta distancia empiezan los efectos
const RADIO_LINTERNA_OFF: float = 6.0      # metros: la linterna se apaga
const HISTERESIS_LINTERNA: float = 2.0     # debes alejarte 2 m más para que se prenda otra vez
const VENTANA_HUIDA: float = 10.0          # segundos de huida tras gastar el escudo
# Volumen (dB) de los bucles según la cercanía: de lejos (min) a encima del enemigo (max).
const VOL_RESPIRACION_MIN: float = -20.0
const VOL_RESPIRACION_MAX: float = 9.0     # la respiración domina
const VOL_SUSURROS_MIN: float = -4.0      # MIN = MAX: volumen alto y constante
const VOL_SUSURROS_MAX: float = -4.0
const DEBUG_TECLA_ATAQUE: bool = true      # H simula un golpe del enemigo (quítalo cuando exista el enemigo)

# --- Pasos ---
const PASOS_POR_PASO: bool = false         # false = un audio continuo mientras caminas; true = un audio por paso
const DIST_PASO: float = 2.2               # metros entre pasos (solo si PASOS_POR_PASO es true)

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

# Persecución: los asigna mapa_3d.gd.
var enemigo: Node3D
var efectos_cercania: bool = false
var cercania: float = 0.0              # 0 = lejos, 1 = encima del enemigo (suavizado)
var distancia_enemigo: float = INF
var linterna_apagada: bool = false
var en_ventana_huida: bool = false     # el enemigo puede consultarlo (p. ej. para quedarse quieto)
var tiempo_huida: float = 0.0

var _pitch: float = 0.0
var _enfriamiento: float = 0.0
var _flash: OmniLight3D
var _dist_paso: float = 0.0
var _snd_respiracion: AudioStreamPlayer
var _snd_susurros: AudioStreamPlayer
var _snd_reloj: AudioStreamPlayer
var _snd_paso_caminar: AudioStreamPlayer
var _snd_paso_correr: AudioStreamPlayer


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

	# Bucles de audio (null si todavía no pusiste el archivo en Music/Sfx).
	_snd_respiracion = Sonidos.crear_bucle(self, "respiracion", -40.0)
	_snd_susurros = Sonidos.crear_bucle(self, "susurros", -40.0)
	_snd_reloj = Sonidos.crear_bucle(self, "reloj", 0.0)
	if not PASOS_POR_PASO:
		_snd_paso_caminar = Sonidos.crear_bucle(self, "paso_caminar", -6.0)
		_snd_paso_correr = Sonidos.crear_bucle(self, "paso_correr", -3.0)

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
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			alternar_arma()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				equipar(Arma.LINTERNA)
			KEY_2:
				equipar(Arma.PISTOLA)
			KEY_R:
				alternar_radar()
			KEY_H:
				if DEBUG_TECLA_ATAQUE:
					print("[DEBUG] golpe simulado -> letal: ", recibir_ataque())
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

	_sonido_pasos(delta)
	_actualizar_persecucion(delta)

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


# ---------- Persecución: cercanía, respiración, linterna y ventana de huida ----------

func _actualizar_persecucion(delta: float) -> void:
	var d: float = INF
	if efectos_cercania and enemigo != null and is_instance_valid(enemigo):
		d = Vector2(global_position.x - enemigo.global_position.x,
			global_position.z - enemigo.global_position.z).length()
	distancia_enemigo = d
	var objetivo: float = clampf(1.0 - d / RADIO_CERCANIA, 0.0, 1.0)
	cercania = lerpf(cercania, objetivo, 1.0 - exp(-6.0 * delta))

	# La linterna se apaga al acercarse el enemigo y vuelve (con su sonido) al alejarte.
	if not linterna_apagada and d < RADIO_LINTERNA_OFF:
		_poner_linterna(false)
	elif linterna_apagada and d > RADIO_LINTERNA_OFF + HISTERESIS_LINTERNA:
		_poner_linterna(true)

	# Respiración y susurros suenan a la vez y suben de volumen mientras más cerca está el enemigo.
	var cerca: bool = cercania > 0.03 and not en_ventana_huida
	_bucle_cercania(_snd_respiracion, cerca, VOL_RESPIRACION_MIN, VOL_RESPIRACION_MAX)
	_bucle_cercania(_snd_susurros, cerca, VOL_SUSURROS_MIN, VOL_SUSURROS_MAX)

	if en_ventana_huida:
		tiempo_huida -= delta
		if tiempo_huida <= 0.0:
			_terminar_ventana_huida()


func _bucle_cercania(p: AudioStreamPlayer, activo: bool, db_min: float, db_max: float) -> void:
	if p == null:
		return
	if activo:
		p.volume_db = lerpf(db_min, db_max, cercania)
		if not p.playing:
			p.play()
	elif p.playing:
		p.stop()


func _poner_linterna(encendida: bool) -> void:
	linterna_apagada = not encendida
	_actualizar_linterna()
	Sonidos.reproducir(self, "linterna_encender" if encendida else "linterna_apagar", -3.0)
	linterna_cambiada.emit(encendida)


func _iniciar_ventana_huida() -> void:
	en_ventana_huida = true
	tiempo_huida = VENTANA_HUIDA
	if _snd_reloj != null:
		_snd_reloj.play()
	ventana_huida_iniciada.emit()


func _terminar_ventana_huida() -> void:
	en_ventana_huida = false
	tiempo_huida = 0.0
	if _snd_reloj != null:
		_snd_reloj.stop()
	ventana_huida_terminada.emit()


# El enemigo llama a esto al alcanzarte. Devuelve true si el ataque es LETAL.
# - Durante la ventana de huida eres invulnerable.
# - Con escudo: se gasta, empieza la ventana de huida de 10 s y sobrevives.
func recibir_ataque() -> bool:
	if en_ventana_huida:
		return false
	if tiene_escudo:
		tiene_escudo = false
		Sonidos.reproducir(self, "escudo_roto")
		Sonidos.reproducir(self, "implosion")   # justo al inicio del golpe, antes de que empiece el reloj
		escudo_roto.emit()
		_iniciar_ventana_huida()
		return false
	return true


# ---------- Pasos ----------

func _sonido_pasos(delta: float) -> void:
	var rapidez: float = Vector2(velocity.x, velocity.z).length()
	var moviendo: bool = is_on_floor() and rapidez > 0.5
	var corriendo: bool = Input.is_physical_key_pressed(KEY_SHIFT)
	if PASOS_POR_PASO:
		if not moviendo:
			_dist_paso = DIST_PASO * 0.6   # al empezar a caminar suena un paso enseguida
			return
		_dist_paso += rapidez * delta
		if _dist_paso >= DIST_PASO:
			_dist_paso = 0.0
			Sonidos.reproducir(self, "paso_correr" if corriendo else "paso_caminar", -4.0)
	else:
		_bucle_paso(_snd_paso_caminar, moviendo and not corriendo)
		_bucle_paso(_snd_paso_correr, moviendo and corriendo)


func _bucle_paso(p: AudioStreamPlayer, debe_sonar: bool) -> void:
	if p == null:
		return
	if debe_sonar and not p.playing:
		p.play()
	elif not debe_sonar and p.playing:
		p.stop()


# ---------- Perks y armas ----------

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
	Sonidos.reproducir(self, "recoger_item", -2.0)
	perk_recogido.emit(tipo)


func equipar(a: int) -> void:
	if a == Arma.PISTOLA and not tiene_pistola:
		return
	if a == arma_actual:
		return
	arma_actual = a
	_actualizar_linterna()
	arma_cambiada.emit(a)


# Rueda del mouse: pasa de la linterna a la pistola y viceversa (si ya tienes la pistola).
func alternar_arma() -> void:
	equipar(Arma.PISTOLA if arma_actual == Arma.LINTERNA else Arma.LINTERNA)


func alternar_radar() -> void:
	if tiene_radar:
		radar_activo = not radar_activo


func disparar() -> void:
	if arma_actual != Arma.PISTOLA or balas <= 0 or _enfriamiento > 0.0:
		return
	balas -= 1
	_enfriamiento = CADENCIA
	Sonidos.reproducir(self, "disparo", 0.0, 0.05)
	disparo_realizado.emit()
	_destello()
	var origen: Vector3 = camara.global_position
	var destino: Vector3 = origen - camara.global_transform.basis.z * 40.0
	var excluir: Array[RID] = [get_rid()]
	var consulta := PhysicsRayQueryParameters3D.create(origen, destino, 1, excluir)
	var impacto: Dictionary = get_world_3d().direct_space_state.intersect_ray(consulta)
	if not impacto.is_empty() and impacto["collider"].has_method("recibir_disparo"):
		impacto["collider"].recibir_disparo()    # el enemigo implementará este método


func _actualizar_linterna() -> void:
	if linterna_apagada:
		linterna.light_energy = 0.0
		return
	var f: float = 1.0 if arma_actual == Arma.LINTERNA else LINTERNA_CON_PISTOLA
	linterna.light_energy = LINTERNA_ENERGIA * f


func _destello() -> void:
	_flash.light_energy = 6.0
	create_tween().tween_property(_flash, "light_energy", 0.0, 0.1)
