class_name Abaddon
extends CharacterBody3D
# Abaddon. Usa Dijkstra (Grafo.dijkstra) para hallar el camino más corto hacia la celda
# actual del jugador.
#
# VELOCIDADES (equilibrio de angustia):
#   - Jugador caminando : 4.2 m/s   ← el enemigo en VELOCIDAD_PERSEGUIR (4.8) lo supera
#   - Jugador corriendo : 7.0 m/s   ← el enemigo en VELOCIDAD_PERSEGUIR lo pierde de vista
#   → Así caminando hay tensión constante; corriendo el jugador gana distancia pero agota stamina.
#
# SPRITE 2D (Abaddon billboard):
#   1. Crea un Sprite3D (o AnimatedSprite3D) como hijo de este nodo en la escena.
#   2. Asígnalo al export [sprite] desde el Inspector.
#   3. Ajusta [sprite_escala] para que encaje con la altura de los muros (alto_muro ≈ 3.0 m).
#   4. El Sprite3D debe tener billboard = BILLBOARD_ENABLED y no_depth_test = true
#      para que siempre mire al jugador y no quede tapado por el suelo.
#
# ASSET DEL SPRITE:
#   res://Assets/Chars/abaddon_sprite.png  ← imagen del enemigo (billboard 2D)
#   Si no existe, se muestra la cápsula provisional.

signal alcanzo_jugador
signal aturdido
signal recuperado

# --- Velocidades ---
@export var velocidad_perseguir: float = 4.8   # m/s: ligeramente mayor que VELOCIDAD_CAMINAR del jugador
@export var velocidad_aturdido: float = 0.0    # quieto

# Compatibilidad: el campo 'velocidad' sigue existiendo para no romper referencias externas.
var velocidad: float:
	get: return velocidad_perseguir

@export var gravedad: float = 20.0
@export var recalculo: float = 0.25
@export var distancia_ataque: float = 1.1
@export var aturdimiento_min: float = 2.0
@export var aturdimiento_max: float = 4.0

# --- Sprite 2D (asignar desde Inspector) ---
# Escala aplicada al sprite. Ajústala para que Abaddon llene visualmente la altura del muro.
@export var sprite_escala: Vector3 = Vector3(1.8, 2.4, 1.0)
@export var sprite: Node3D = null   # arrastra tu Sprite3D/AnimatedSprite3D aquí

var mapa: Mapa3D
var jugador: Jugador
var ruta: Array[Vector2i] = []
var esta_aturdido: bool = false
var esta_congelado: bool = false

var _t_recalculo: float = 0.0
var _t_aturdido: float = 0.0
var _t_ataque: float = 0.0
var _mat: StandardMaterial3D
var _malla_provisional: MeshInstance3D
var _luz: OmniLight3D
var _color_normal: Color = Color(1.0, 0.1, 0.1)
var _color_aturdido: Color = Color(1.0, 0.9, 0.1)
var _snd_bucle: AudioStreamPlayer


func _ready() -> void:
	# ── Colisión ────────────────────────────────────────────────────────
	var col := CollisionShape3D.new()
	var capsula := CapsuleShape3D.new()
	capsula.radius = 0.4
	capsula.height = 1.8
	col.shape = capsula
	col.position.y = 0.9
	add_child(col)

		# ── Sprite 2D / representación visual ───────────────────────────────
	if sprite != null:
		# Sprite asignado desde el Inspector: ajustar posición y escala.
		sprite.position.y = 0.9
		sprite.scale = sprite_escala
		# Si es Sprite3D, activar billboard para que siempre mire al jugador.
		if sprite is Sprite3D or sprite is AnimatedSprite3D:
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.no_depth_test = false
		# Cargar textura si no fue asignada en el Inspector
		if sprite is Sprite3D and sprite.texture == null:
			if ResourceLoader.exists("res://Assets/Chars/monster.png"):
				sprite.texture = load("res://Assets/Chars/monster.png")
	else:
		var ruta_tex: String = "res://Assets/Chars/monster.png"
		var tex: Texture2D = load(ruta_tex) if ResourceLoader.exists(ruta_tex) else null
		print("[Abaddon] png encontrado: ", tex != null, " | tamaño: ", tex.get_size() if tex != null else "—")
		if tex != null:
			var s3d := Sprite3D.new()
			s3d.texture = tex
			s3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s3d.shaded = false
			s3d.double_sided = true
			s3d.pixel_size = sprite_escala.y / float(tex.get_height())
			s3d.position.y = sprite_escala.y * 0.5
			add_child(s3d)
			sprite = s3d
			print("[Abaddon] sprite creado | pixel_size: ", s3d.pixel_size, " | alto en metros: ", tex.get_height() * s3d.pixel_size)
		else:
			# Malla cápsula PROVISIONAL mientras no hay sprite.
			_malla_provisional = MeshInstance3D.new()
			var forma := CapsuleMesh.new()
			forma.radius = 0.4
			forma.height = 1.8
			_malla_provisional.mesh = forma
			_malla_provisional.position.y = 0.9
			_mat = StandardMaterial3D.new()
			_mat.emission_enabled = true
			_malla_provisional.material_override = _mat
			add_child(_malla_provisional)

	# ── Luz ambiental ────────────────────────────────────────────────────
	_luz = OmniLight3D.new()
	_luz.omni_range = 4.0
	_luz.position.y = 1.2
	add_child(_luz)
	_pintar(_color_normal)

	# ── Audio ─────────────────────────────────────────────────────────────
	_snd_bucle = Sonidos.crear_bucle(self, "abaddon_gruñido", -12.0)


func _physics_process(delta: float) -> void:
	if mapa == null or jugador == null:
		return
	_t_ataque = maxf(0.0, _t_ataque - delta)

	if esta_congelado:
		velocity.x = 0.0
		velocity.z = 0.0
	elif esta_aturdido:
		_t_aturdido -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _t_aturdido <= 0.0:
			esta_aturdido = false
			_pintar(_color_normal)
			_t_recalculo = 0.0
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
	_actualizar_audio()


func celda_actual() -> Vector2i:
	return Vector2i(floori(global_position.x / mapa.tam_celda), floori(global_position.z / mapa.tam_celda))


func _recalcular_ruta() -> void:
	ruta = Grafo.dijkstra(mapa.matriz, celda_actual(), jugador.celda_actual)


func _seguir_ruta() -> void:
	var objetivo: Vector3
	if ruta.size() >= 2:
		objetivo = mapa.celda_a_mundo(ruta[1])
		if ruta.size() == 2 and ruta[1] == jugador.celda_actual:
			objetivo = jugador.global_position
	else:
		objetivo = jugador.global_position
	var dir: Vector3 = objetivo - global_position
	dir.y = 0.0
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity.x = dir.x * velocidad_perseguir
		velocity.z = dir.z * velocidad_perseguir
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
		_t_ataque = 1.5
		if jugador.recibir_ataque():
			alcanzo_jugador.emit()


func recibir_disparo() -> void:
	esta_aturdido = true
	_t_aturdido = randf_range(aturdimiento_min, aturdimiento_max)
	_pintar(_color_aturdido)
	aturdido.emit()


func congelar(valor: bool) -> void:
	esta_congelado = valor
	if _malla_provisional != null:
		var col: Color = Color(0.3, 0.55, 1.0) if valor else _color_normal
		_pintar(col)


func _pintar(c: Color) -> void:
	if _mat != null:
		_mat.albedo_color = c
		_mat.emission = c
	_luz.light_color = c
	_luz.light_energy = 1.2


func _actualizar_audio() -> void:
	if _snd_bucle == null:
		return
	var moviendose: bool = Vector2(velocity.x, velocity.z).length() > 0.3
	if moviendose and not esta_aturdido and not esta_congelado:
		if not _snd_bucle.playing:
			_snd_bucle.play()
	else:
		if _snd_bucle.playing:
			_snd_bucle.stop()
