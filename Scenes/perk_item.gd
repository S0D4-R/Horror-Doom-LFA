class_name PerkItem
extends Area3D
# Perk flotante en el mapa. Brilla para verse en la oscuridad y se recoge al tocarlo.

signal recogido(tipo: int)   # el mapa lo escucha para regenerar el perk más tarde

@export var tipo: int = Perks.Tipo.PISTOLA

var _visual: MeshInstance3D
var _sprite: Sprite3D
var _t: float = 0.0


func _ready() -> void:
	var color: Color = Perks.color(tipo)

	var col := CollisionShape3D.new()
	var esfera := SphereShape3D.new()
	esfera.radius = 0.9
	col.shape = esfera
	col.position.y = 1.0
	add_child(col)

	_visual = MeshInstance3D.new()
	_visual.mesh = _crear_malla()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	_visual.material_override = mat
	_visual.position.y = 1.0
	add_child(_visual)

	var icono: Texture2D = Perks.icono(tipo)
	if icono != null:   # con ícono: se oculta la figura de color y se muestra la imagen
		_visual.visible = false
		_sprite = Sprite3D.new()
		_sprite.texture = icono
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.shaded = false
		_sprite.pixel_size = 0.9 / float(maxi(icono.get_width(), icono.get_height()))   # ~0.9 m de alto
		_sprite.position.y = 1.0
		add_child(_sprite)

	var luz := OmniLight3D.new()
	luz.light_color = color
	luz.light_energy = 1.2
	luz.omni_range = 5.0
	luz.position.y = 1.0
	add_child(luz)

	body_entered.connect(_on_body_entered)


# Cada perk tiene una forma distinta para reconocerlo de lejos.
func _crear_malla() -> Mesh:
	if tipo == Perks.Tipo.RADAR:
		var aro := TorusMesh.new()
		aro.inner_radius = 0.18
		aro.outer_radius = 0.38
		return aro
	var caja := BoxMesh.new()
	if tipo == Perks.Tipo.ESCUDO:
		caja.size = Vector3(0.5, 0.65, 0.1)
	else:
		caja.size = Vector3(0.6, 0.3, 0.2)
	return caja


func _process(delta: float) -> void:
	_t += delta
	_visual.rotation.y = _t * 1.5
	_visual.position.y = 1.0 + sin(_t * 2.0) * 0.12
	if _sprite != null:
		_sprite.position.y = 1.0 + sin(_t * 2.0) * 0.12


func _on_body_entered(body: Node3D) -> void:
	if body is Jugador:
		body.recoger_perk(tipo)
		recogido.emit(tipo)
		queue_free()
