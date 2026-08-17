class_name CardArtMap
extends RefCounted
## Maps a card's def_id to its shipped face art under res://ui/art/cards --
## full pre-made card images (art, name, and category framing all baked in
## by the artist) that CardFace shows in place of the procedural
## CardArtPlaceholder + name label whenever one exists. Cards with no
## shipped art yet (currently the joker ingredients, added after this art
## set was delivered) fall back to the procedural rendering unchanged.
##
## Presentational only, same as CardCategoryMap -- the engine has no concept
## of this mapping.

const BACK_PATH := "res://ui/art/cards/MLcard_back.png"

const _PATHS := {
	"oil": "res://ui/art/cards/MLcard_ingr_oil.png",
	"island_spice_blend": "res://ui/art/cards/MLcard_ingr_spice.png",
	"garlic": "res://ui/art/cards/MLcard_ingr_garlic.png",
	"chicken": "res://ui/art/cards/MLcard_ingr_chicken.png",
	"salt_pepper": "res://ui/art/cards/MLcard_ingr_saltpepper.png",
	"onion": "res://ui/art/cards/MLcard_ingr_onion.png",
	"chili": "res://ui/art/cards/MLcard_ingr_chili.png",
	"coconut_milk": "res://ui/art/cards/MLcard_ingr_coconutmilk.png",
	"fish": "res://ui/art/cards/MLcard_ingr_fish.png",
	"fresh_herbs": "res://ui/art/cards/MLcard_ingr_herbs.png",
	"tomato": "res://ui/art/cards/MLcard_ingr_tomato.png",
	"beef": "res://ui/art/cards/MLcard_ingr_beef.png",
	"goat": "res://ui/art/cards/MLcard_ingr_goat.png",
	"lime": "res://ui/art/cards/MLcard_ingr_lime.png",
	"eggs": "res://ui/art/cards/MLcard_ingr_eggs.png",
	"simmering": "res://ui/art/cards/MLcard_prep_simmer.png",
	"marinating": "res://ui/art/cards/MLcard_prep_marinate.png",
	"grinding": "res://ui/art/cards/MLcard_prep_grind.png",
	"mixing": "res://ui/art/cards/MLcard_prep_mix.png",
	"frying": "res://ui/art/cards/MLcard_prep_fry.png",
	"chopping": "res://ui/art/cards/MLcard_prep_chop.png",
}

## "" if def_id has no shipped art (falls back to CardArtPlaceholder).
static func path_for(def_id: String) -> String:
	return _PATHS.get(def_id, "")
