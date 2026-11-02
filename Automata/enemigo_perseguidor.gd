class_name EnemigoPerseguidor
extends CharacterBody3D 
# Definición de estados del autómata
enum Estado { IDLE, ESPERANDO, PERSIGUIENDO }
var estado_actual: Estado = Estado.IDLE

@export var distancia_activacion: float = 10.0  # El "cierto espacio" mínimo para que despierte
var contador_pasos_jugador: int = 0
var jugador: Node3D = null

func _ready() -> void:
	# Busca al jugador en la escena principal
	jugador = get_node_or_null("../Jugador")

# Esta función es llamada desde el script del Jugador cada vez que da un paso (cambia de celda)
func registrar_movimiento_jugador() -> void:
	if not jugador:
		return

	# 1. Medir la distancia ("cierto espacio") con el jugador
	var distancia = global_position.distance_to(jugador.global_position)

	# Si el jugador está dentro del radio de detección
	if distancia <= distancia_activacion:
		contador_pasos_jugador += 1
		
		# 2. Condición del autómata: Se mueve cada 2 movimientos del jugador
		if contador_pasos_jugador >= 2:
			estado_actual = Estado.PERSIGUIENDO
			ejecutar_persecucion()
			contador_pasos_jugador = 0 # Reiniciamos el contador para los siguientes 2 pasos
		else:
			estado_actual = Estado.ESPERANDO
			print("El monstruo te mira y espera... (Movimiento del jugador: ", contador_pasos_jugador, ")")
	else:
		estado_actual = Estado.IDLE
		contador_pasos_jugador = 0

func ejecutar_persecucion() -> void:
	# Lógica para que el monstruo avance un paso hacia la posición del jugador
	var direccion = (jugador.global_position - global_position).normalized()
	
	# Si te acercas por casillas exactas, puedes sumarle la medida de tu celda (ej: 2.0 unidades)
	global_position += direccion * 2.0 
	print("¡El monstruo se ha movido hacia ti!")
