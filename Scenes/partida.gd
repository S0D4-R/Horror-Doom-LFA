class_name Partida
extends RefCounted
# Datos compartidos entre el menú y el juego. Usa variables estáticas, así que NO hace falta
# registrar un autoload: sobreviven al cambio de escena.

enum Modo { U_R_D4MN3D, SUPERVIVENCIA, DIJKSTRA }   # el orden debe coincidir con MODOS

const ESCENA_MENU: String = "res://Scenes/main_menu_interactive.tscn"
const ESCENA_JUEGO: String = "res://Scenes/map_palace.tscn"

# Reglas provisionales: se implementan en el juego según el modo elegido.
const MODOS: Array = [
	{
		"nombre": "U R D4MN3D",
		"desc": "Unus hostis te sine requie persequitur. Quo propior est, eo magis mundus rubescit, eo fortius spiras atque citius lanterna tua exstinguitur. Fuge priusquam te adsequatur.",
	},
	{
		"nombre": "SUPERVIVENCIA",
		"desc": "Nullus est exitus. Quam diutissime perfer, dum commoda te vivum manere iuvant.",
	},
	{
		"nombre": "Dijkstra",
		"desc": "Respice post aulaeum, aspectus haud multum tibi nocebit...",
	},
]

const MAPAS: Array = [
	{
		"nombre": "PASILLOS",
		"archivo": "res://Maps/mapa1_pasillos.txt",
		"tam": "61 x 37",
		"nodos": 1180,
		"desc": "Un laberinto interminable de corredores idénticos. Todo se parece a todo, y nadie sabe cuánto lleva perdido.",
	},
	{
		"nombre": "CEMENTERIO",
		"archivo": "res://Maps/mapa2_cementerio.txt",
		"tam": "40 x 40",
		"nodos": 1195,
		"desc": "Lápidas, criptas y un mausoleo en el centro. Terreno abierto: nada te esconde de lo que te sigue.",
	},
	{
		"nombre": "PLAZA",
		"archivo": "res://Maps/mapa3_plaza.txt",
		"tam": "61 x 61",
		"nodos": 2483,
		"desc": "Una plaza monumental con una gran fuente central, edificios cerrados a los lados y callejones en penumbra.",
	},
	{
		"nombre": "METRO",
		"archivo": "res://Maps/mapa4_metro.txt",
		"tam": "81 x 53",
		"nodos": 2933,
		"desc": "Una estación de metro abandonada con carteles japoneses, anuncios, andenes, columnas y un tren detenido.",
	},
]

static var activa: bool = false      # true cuando se llegó al juego desde el menú
static var modo: int = Modo.U_R_D4MN3D
static var indice_mapa: int = 0


static func archivo_mapa() -> String:
	return MAPAS[indice_mapa]["archivo"]


static func nombre_modo() -> String:
	return MODOS[modo]["nombre"]
