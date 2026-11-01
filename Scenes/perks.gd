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
