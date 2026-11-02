class_name EnemigoPerseguidor
extends Abaddon
# ─── Módulo de movimiento por pasos ───────────────────────────────────────────
# Hereda TODO lo de Abaddon (Dijkstra, aturdimiento, sprite, audio, luz…).
# Añade el autómata de estados que mueve a Abaddon UNA celda cada 2 pasos
# del jugador y solo cuando está dentro del radio de activación.
#
# Compatibilidad con mapa_3d.gd
# ─────────────────────────────
# mapa_3d ya declara:  var enemigo_nodo: Perseguidor
# Como EnemigoPerseguidor extiende Abaddon (que a su vez extiende CharacterBody3D)
# y Perseguidor fue renombrado a Abaddon, la variable de mapa_3d debe cambiar a:
#     var enemigo_nodo: Abaddon
# Así desaparece el error "Expression is of type 'Perseguidor' so it can't be
# of type 'MeshInstance3D'" que surgía porque _congelar_enemigo comparaba con
# MeshInstance3D en lugar de llamar a congelar(). Ahora Abaddon sí implementa
# congelar(), así que mapa_3d entra por la rama correcta.

# Definición de estados del autómata
enum Estado { IDLE, ESPERANDO, PERSIGUIENDO }
var estado_actual: Estado = Estado.IDLE

@export var distancia_activacion: float = 10.0  # radio mínimo para que despierte

var contador_pasos_jugador: int = 0


func _ready() -> void:
	# Inicializar todo lo de Abaddon (colisión, sprite/malla, luz, audio)
	super._ready()
	# El jugador se asignará desde mapa_3d igual que antes.
	# Si quieres buscar automáticamente (útil en pruebas):
	#   jugador = get_node_or_null("../Jugador")


# ── Autómata de pasos ────────────────────────────────────────────────────────
# Esta función es llamada desde el script del Jugador cada vez que cambia de celda.
func registrar_movimiento_jugador() -> void:
	if not jugador:
		return
	if esta_congelado or esta_aturdido:
		return   # no reacciona durante la ventana de huida ni mientras está aturdido

	var distancia: float = global_position.distance_to(jugador.global_position)

	if distancia <= distancia_activacion:
		contador_pasos_jugador += 1

		if contador_pasos_jugador >= 2:
			estado_actual = Estado.PERSIGUIENDO
			_ejecutar_paso()
			contador_pasos_jugador = 0
		else:
			estado_actual = Estado.ESPERANDO
			print("Abaddon te observa en silencio… (%d/2)" % contador_pasos_jugador)
	else:
		estado_actual = Estado.IDLE
		contador_pasos_jugador = 0


# Avanza exactamente una celda en dirección al jugador.
# Complementa (no reemplaza) el seguimiento continuo de Abaddon:
# si el modo es U_R_D4MN3D, _physics_process ya mueve con Dijkstra;
# este método sirve para el modo SUPERVIVENCIA o para testear el autómata solo.
func _ejecutar_paso() -> void:
	var direccion: Vector3 = (jugador.global_position - global_position).normalized()
	global_position += direccion * mapa.tam_celda if mapa != null else direccion * 2.0
	print("¡Abaddon avanza hacia ti!")
