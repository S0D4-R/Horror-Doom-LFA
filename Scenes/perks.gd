class_name Perks
extends RefCounted
# Catálogo de perks. Para agregar uno nuevo: añade el tipo al enum y su nombre y color abajo.

enum Tipo { PISTOLA, RADAR, ESCUDO }


static func nombre(t: int) -> String:
	if t == Tipo.PISTOLA:
		return "Pistola"
	if t == Tipo.RADAR:
		return "Radar"
	if t == Tipo.ESCUDO:
		return "Escudo"
	return "?"


static func color(t: int) -> Color:
	if t == Tipo.PISTOLA:
		return Color(1.0, 0.55, 0.1)
	if t == Tipo.RADAR:
		return Color(0.2, 1.0, 0.3)
	if t == Tipo.ESCUDO:
		return Color(0.2, 0.6, 1.0)
	return Color.WHITE


# --- Íconos ---
# Pon una imagen cuadrada con fondo transparente (recomendado 128x128) en CARPETA_ICONOS
# con el nombre indicado en ICONOS. Sirve .png, .webp o .svg. Si no existe, se usa el aspecto
# anterior (cajas de colores y texto), así que puedes ir agregándolos uno por uno.
const CARPETA_ICONOS: String = "res://Assets/Icons/"
const ICONOS: Dictionary = {
	Tipo.PISTOLA: "perk_pistola",
	Tipo.RADAR: "perk_radar",
	Tipo.ESCUDO: "perk_escudo",
}


static func icono(t: int) -> Texture2D:
	var base: String = ICONOS.get(t, "")
	if base == "":
		return null
	for ext in [".png", ".webp", ".svg"]:
		var ruta: String = CARPETA_ICONOS + base + ext
		if ResourceLoader.exists(ruta):
			return load(ruta)
	return null


# Todos los tipos de perk: el mapa los usa para colocarlos y regenerarlos.
# Si agregas un perk nuevo al enum, agrégalo aquí también.
static func todos() -> Array:
	return [Tipo.PISTOLA, Tipo.RADAR, Tipo.ESCUDO]
