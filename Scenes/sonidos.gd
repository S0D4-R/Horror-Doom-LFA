class_name Sonidos
extends RefCounted
# Sistema de audio. Cada evento del juego tiene un NOMBRE de archivo (sin extensión) en ARCHIVOS.
# Pon tus audios en res://Music/Sfx/ con esos nombres; sirve .ogg, .wav o .mp3 (en ese orden).
# Si un audio todavía no existe, simplemente no suena (avisa una sola vez en la consola de salida).
# Para usar otro nombre de archivo, cambia el valor a la derecha de cada entrada.

const CARPETA: String = "res://Music/"
const EXTENSIONES: Array = [".ogg", ".wav", ".mp3"]

const ARCHIVOS: Dictionary = {
	# ---- Jugador ----
	"paso_caminar": "steps",                                              # suena mientras caminas
	"paso_correr": "Running footsteps [QnJ26_ZlEbo]",                     # suena mientras corres (Shift)
	"recoger_item": "pickupitem",                                         # al recoger un perk
	"linterna_encender": "Flashlight Sound Effect sfx [-38q978nFnc]",     # al volver a prenderse la linterna (cuando te alejas del enemigo)
	"linterna_apagar": "Flashlight Sound Effect sfx [-38q978nFnc]",       # OPCIONAL: cuando se apaga al acercarse el enemigo
	"disparo": "shot",                                                    # OPCIONAL: al disparar la pistola
	"escudo_roto": "escudo_roto",                                         # OPCIONAL: golpe seco en el instante en que el escudo se gasta
	"implosion": "Electrical explosion - SOUND EFFECT - [5dOplLd4-vU]",                                             # NUEVO: implosión justo al recibir el golpe con escudo (cambia el nombre por el de tu archivo)
	# ---- Bucles (se repiten solos mientras dura el efecto) ----
	"respiracion": "heavy breathing sound effect [54Pqc-Abgas]",          # cerca del enemigo: más fuerte mientras más cerca
	"susurros": "whispers",                                               # cerca del enemigo, a la vez que la respiración
	"reloj": "ticking",                                                   # durante los 10 s de huida tras gastar el escudo
	# ---- Menú ----
	"ui_select": "select",                                                # al moverte entre botones (teclado o mouse), en el menú principal y en el de pausa
	"ui_click": "accept",                                                 # al aceptar / hacer clic en cualquier botón
	"ui_comenzar": "accept",                                              # al pulsar COMENZAR (se reproduce sobre la raíz para que no se corte al cargar el juego)
}

static var _cache: Dictionary = {}
static var _avisados: Dictionary = {}


static func _buscar(nombre: String) -> AudioStream:
	if _cache.has(nombre):
		return _cache[nombre]
	var base: String = ARCHIVOS.get(nombre, nombre)
	for ext in EXTENSIONES:
		var ruta: String = CARPETA + base + ext
		if ResourceLoader.exists(ruta):
			var s: AudioStream = load(ruta)
			_cache[nombre] = s
			return s
	if not _avisados.has(nombre):
		_avisados[nombre] = true
		push_warning("Sonidos: falta el audio '%s' (busqué %s%s con .ogg, .wav o .mp3)" % [nombre, CARPETA, base])
	return null


# Si existe el bus "SFX" (pestaña Audio de Godot) lo usa; si no, el bus principal.
static func _bus() -> StringName:
	return &"SFX" if AudioServer.get_bus_index("SFX") != -1 else &"Master"


# Reproduce un sonido una vez. "padre" es el nodo que lo contiene: si el sonido debe seguir
# sonando después de cambiar de escena, pasa get_tree().root.
static func reproducir(padre: Node, nombre: String, volumen_db: float = 0.0, variacion_tono: float = 0.0) -> void:
	var s: AudioStream = _buscar(nombre)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volumen_db
	p.pitch_scale = 1.0 + randf_range(-variacion_tono, variacion_tono)
	p.bus = _bus()
	p.process_mode = Node.PROCESS_MODE_ALWAYS   # que también suene con el juego en pausa (menú de pausa)
	padre.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# Crea un reproductor que se repite en bucle. NO lo inicia: quien lo crea llama a play() y stop().
# Devuelve null si el audio todavía no existe (hay que comprobarlo antes de usarlo).
static func crear_bucle(padre: Node, nombre: String, volumen_db: float = 0.0) -> AudioStreamPlayer:
	var s: AudioStream = _buscar(nombre)
	if s == null:
		return null
	_activar_bucle(s)
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volumen_db
	p.bus = _bus()
	padre.add_child(p)
	return p


static func _activar_bucle(s: AudioStream) -> void:
	if s is AudioStreamOggVorbis:
		s.loop = true
	elif s is AudioStreamMP3:
		s.loop = true
	elif s is AudioStreamWAV:
		var bytes: int = 2 if s.format == AudioStreamWAV.FORMAT_16_BITS else 1
		if s.stereo:
			bytes *= 2
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.data.size() / float(bytes))
