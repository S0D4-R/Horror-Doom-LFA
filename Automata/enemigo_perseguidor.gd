class_name EnemigoPerseguidor
extends Node2D

# Estados del autómata
enum Estado { IDLE, ESPERANDO, PERSIGUIENDO }
var estado_actual: Estado = Estado.IDLE

@export var distancia_activacion: float = 150.0  # El espacio mínimo para empezar a rastrear
var contador_movimientos_jugador: int = 0
var posicion_en_grilla: Vector2i = Vector2i.ZERO # O Vector2 según cómo manejes tu mapa

# Referencia al jugador (se puede asignar al iniciar)
var jugador: Node2D = null

func _ready() -> void:
	# Buscamos al jugador en la escena (ajusta la ruta según tu estructura)
	jugador = get_node_or_null("../Jugador") 

# Esta función debe llamarse cada vez que EL JUGADOR se mueva con éxito
To do: registrar_movimiento_jugador() -> void:
	if not jugador:
		return

	# 1. Medir el espacio (distancia) actual con el jugador
	var distancia = global_position.distance_to(jugador.global_position)

	# Si está dentro del rango de espacio permitido, el autómata se activa
	if distancia <= distancia_activacion:
		contador_movimientos_jugador += 1
		
		# Se mueve cada 2 movimientos del jugador
		if contador_movimientos_jugador >= 2:
			estado_actual = Estado.PERSIGUIENDO
			ejecutar_paso_persecucion()
			contador_movimientos_jugador = 0 # Reiniciamos el contador
		else:
			estado_actual = Estado.ESPERANDO
	else:
		estado_actual = Estado.IDLE
		contador_movimientos_jugador = 0

func ejecutar_paso_persecucion() -> void:
	# Lógica para acercarse una casilla / un paso hacia el jugador
	# Si usas posiciones en pixeles directos:
	var direccion = (jugador.global_position - global_position).normalized()
	global_position += direccion * 32.0 # Asumiendo un tamaño de celda de 32px, ajústalo a tu juego
	
	print("¡El monstruo se ha movido persiguiéndote tras 2 de tus movimientos!")
