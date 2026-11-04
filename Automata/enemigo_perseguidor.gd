class_name EnemigoPerseguidor
extends Abaddon
# ─── Autómata del perseguidor ─────────────────────────────────────────────────
# Máquina de estados finita (con contador de pasos) que gobierna a Abaddon
# usando el grafo de Grafo.gd (celdas de piso = nodos, vecinos 4-dir = aristas).
#
# Q (estados)  : IDLE, ESPERANDO, PERSIGUIENDO, ATURDIDO, CONGELADO
# Σ (eventos)  : JUGADOR_CERCA, JUGADOR_LEJOS, DISPARO, RECUPERADO, CONGELAR, DESCONGELAR
# δ (TRANSICIONES) : tabla (estado, evento) -> estado.  Si el par no está, el estado no cambia.
# q0           : IDLE
#
# Salida (tipo Mealy): al transicionar a PERSIGUIENDO por JUGADOR_CERCA, el enemigo
# avanza UNA celda por la ruta Dijkstra (Grafo.dijkstra) hacia el jugador.
#
# Cómo se mide "cerca": en NODOS DEL GRAFO (largo de la ruta Dijkstra), no en línea recta.
# Así un muro entre ambos cuenta como lejos aunque estén pegados en el plano.
#
# Cableado (lo hace mapa_3d.gd): jugador.celda_cambiada -> registrar_movimiento_jugador()

enum Estado { IDLE, ESPERANDO, PERSIGUIENDO, ATURDIDO, CONGELADO }
enum Evento { JUGADOR_CERCA, JUGADOR_LEJOS, DISPARO, RECUPERADO, CONGELAR, DESCONGELAR }

signal estado_cambiado(anterior: int, nuevo: int, evento: int)

# Función de transición δ. JUGADOR_CERCA no está aquí porque lleva guarda (contador de pasos),
# se resuelve en _siguiente_estado().
const TRANSICIONES: Dictionary = {
	Estado.IDLE: {
		Evento.DISPARO: Estado.ATURDIDO,
		Evento.CONGELAR: Estado.CONGELADO,
	},
	Estado.ESPERANDO: {
		Evento.JUGADOR_LEJOS: Estado.IDLE,
		Evento.DISPARO: Estado.ATURDIDO,
		Evento.CONGELAR: Estado.CONGELADO,
	},
	Estado.PERSIGUIENDO: {
		Evento.JUGADOR_LEJOS: Estado.IDLE,
		Evento.DISPARO: Estado.ATURDIDO,
		Evento.CONGELAR: Estado.CONGELADO,
	},
	Estado.ATURDIDO: {
		Evento.RECUPERADO: Estado.IDLE,
		Evento.CONGELAR: Estado.CONGELADO,
	},
	Estado.CONGELADO: {
		Evento.DESCONGELAR: Estado.IDLE,   # si sigue aturdido se corrige en _siguiente_estado()
	},
}

# Radio de activación medido en celdas del grafo (5 celdas ≈ 10 m con tam_celda = 2).
@export var radio_activacion_celdas: int = 999
# Cuántos pasos del jugador (cambios de celda) hacen falta para que avance una celda.
@export var pasos_por_movimiento: int = 2
# true  = dentro del radio persigue sin pausa con el Dijkstra de Abaddon (estilo U R D4MN3D).
# false = avanza solo de a una celda cada [pasos_por_movimiento] pasos del jugador.
@export var persecucion_continua: bool = true
@export var depurar: bool = true

var estado_actual: Estado = Estado.IDLE
var contador_pasos_jugador: int = 0

var _celda_objetivo: Vector2i = Vector2i.ZERO
var _tiene_objetivo: bool = false
var _velocidad_base: float = 0.0   # velocidad_perseguir original, para poder frenarlo (mapa de pasos)


func _ready() -> void:
	_velocidad_base = velocidad_perseguir
	super._ready()
	recuperado.connect(_on_recuperado)


# ── Entrada de eventos ───────────────────────────────────────────────────────
# Lo llama mapa_3d.gd cada vez que el jugador cambia de celda (señal celda_cambiada).
func registrar_movimiento_jugador(_celda: Vector2i = Vector2i.ZERO) -> void:
	if mapa == null or jugador == null:
		return
	# Ruta enemigo -> jugador sobre el grafo. Se guarda en [ruta], que usa Abaddon.
	ruta = Grafo.dijkstra(mapa.matriz, celda_actual(), jugador.celda_actual)
	var cerca: bool = not ruta.is_empty() and (ruta.size() - 1) <= radio_activacion_celdas
	_procesar(Evento.JUGADOR_CERCA if cerca else Evento.JUGADOR_LEJOS)


func recibir_disparo() -> void:
	super.recibir_disparo()
	_procesar(Evento.DISPARO)


func congelar(valor: bool) -> void:
	super.congelar(valor)
	_procesar(Evento.CONGELAR if valor else Evento.DESCONGELAR)


func _on_recuperado() -> void:
	_procesar(Evento.RECUPERADO)


# ── Núcleo del autómata ──────────────────────────────────────────────────────
func _procesar(evento: Evento) -> void:
	var anterior: Estado = estado_actual
	var siguiente: Estado = _siguiente_estado(evento)

	estado_actual = siguiente
	if siguiente != anterior:
		_al_cambiar_de_estado(siguiente)
		estado_cambiado.emit(anterior, siguiente, evento)
		if depurar:
			print("Abaddon: %s --%s--> %s" % [Estado.keys()[anterior], Evento.keys()[evento], Estado.keys()[siguiente]])

	# Salida de la transición: avanzar una celda.
	if evento == Evento.JUGADOR_CERCA and siguiente == Estado.PERSIGUIENDO:
		_dar_paso()


func _siguiente_estado(evento: Evento) -> Estado:
	if evento == Evento.JUGADOR_CERCA:
		# En ATURDIDO / CONGELADO no reacciona.
		if estado_actual == Estado.ATURDIDO or estado_actual == Estado.CONGELADO:
			return estado_actual
		contador_pasos_jugador += 1
		if contador_pasos_jugador >= _pasos_necesarios():
			contador_pasos_jugador = 0
			return Estado.PERSIGUIENDO
		return Estado.ESPERANDO

	var siguiente: Estado = TRANSICIONES.get(estado_actual, {}).get(evento, estado_actual)
	# Al descongelar, si todavía está aturdido vuelve a ATURDIDO y no a IDLE.
	if evento == Evento.DESCONGELAR and siguiente == Estado.IDLE and esta_aturdido:
		siguiente = Estado.ATURDIDO
	return siguiente


func _pasos_necesarios() -> int:
	return 1 if persecucion_continua else maxi(1, pasos_por_movimiento)


# Acciones de entrada a un estado.
func _al_cambiar_de_estado(nuevo: Estado) -> void:
	if nuevo == Estado.IDLE or nuevo == Estado.ATURDIDO or nuevo == Estado.CONGELADO:
		contador_pasos_jugador = 0
		_tiene_objetivo = false


# Fija como objetivo la siguiente celda de la ruta Dijkstra (ruta[0] es la celda actual).
func _dar_paso() -> void:
	if persecucion_continua or ruta.size() < 2:
		return
	_celda_objetivo = ruta[1]
	_tiene_objetivo = true
	if depurar:
		print("¡Abaddon avanza a la celda %s!" % _celda_objetivo)


# ── Movimiento (sobrescribe los ganchos de Abaddon, el resto se hereda) ─────
# En modo por pasos Abaddon no recalcula la ruta solo: la fija el autómata en cada evento.
func _recalcular_ruta() -> void:
	if persecucion_continua and estado_actual == Estado.PERSIGUIENDO:
		super._recalcular_ruta()


func _seguir_ruta() -> void:
	if persecucion_continua:
		if estado_actual == Estado.PERSIGUIENDO:
			super._seguir_ruta()
		else:
			_detener()
		return

	if not _tiene_objetivo:
		_detener()
		return

	# Si el objetivo es la celda del jugador, va directo hacia él (igual que Abaddon).
	var destino: Vector3 = mapa.celda_a_mundo(_celda_objetivo)
	if _celda_objetivo == jugador.celda_actual:
		destino = jugador.global_position
	var dir: Vector3 = destino - global_position
	dir.y = 0.0

	var margen: float = velocidad_perseguir * get_physics_process_delta_time() * 1.5
	if dir.length() <= margen:
		_tiene_objetivo = false   # llegó al centro de la celda: espera el próximo paso
		_detener()
		return

	dir = dir.normalized()
	velocity.x = dir.x * velocidad_perseguir
	velocity.z = dir.z * velocidad_perseguir
	look_at(global_position + Vector3(dir.x, 0.0, dir.z), Vector3.UP)


func _detener() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


# Multiplica la velocidad de persecución (1.0 = normal, 0.6 = 60 %). Lo usa el mapa de pasos (K).
func set_factor_velocidad(factor: float) -> void:
	velocidad_perseguir = _velocidad_base * factor


func nombre_estado() -> String:
	return Estado.keys()[estado_actual]
