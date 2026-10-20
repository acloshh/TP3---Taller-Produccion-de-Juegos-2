extends Node

const DICCIONARIO_TILES = {
	# TERRENO (TileMapLayer 1)
	"P_SUP_IZQ": Vector2i(1, 5), "P_SUP_MED": Vector2i(2, 5), "P_SUP_DER": Vector2i(3, 5),
	"P_MED_IZQ": Vector2i(1, 6), "P_MED_MED": Vector2i(2, 6), "P_MED_DER": Vector2i(3, 6),
	"P_INF_IZQ": Vector2i(1, 7), "P_INF_MED": Vector2i(2, 7), "P_INF_DER": Vector2i(3, 7),
	
	# INTERACTIVOS (TileMapLayer 2)
	"PASTO_A": Vector2i(0, 1), "PASTO_B": Vector2i(1, 1),
	"ESCALERA_TOP": Vector2i(2, 2), "ESCALERA_MID": Vector2i(2, 3),
	
	# ARBUSTO (4 cuadrantes)
	"ARB_UL": Vector2i(2, 0), "ARB_UR": Vector2i(3, 0),
	"ARB_DL": Vector2i(2, 1), "ARB_DR": Vector2i(3, 1)
}
