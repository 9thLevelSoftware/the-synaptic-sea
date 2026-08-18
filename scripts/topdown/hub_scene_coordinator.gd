extends Node2D
## Hub scene coordinator — creates TileSet at runtime, builds ship layout,
## and wires up camera + player. Entry point for the hub gameplay.

const HubShipBuilderScript = preload("res://scripts/topdown/hub_ship_builder.gd")
const TILE_SIZE := 48

var tilemap: TileMapLayer
var camera_rig: Node2D  # TopDownCameraRig
var player: CharacterBody2D  # TopDownPlayerController
var builder: Node


func _ready() -> void:
	tilemap = get_node_or_null("HubTileMap")
	camera_rig = get_node_or_null("TopDownCameraRig")
	player = get_node_or_null("Player")

	if tilemap:
		var ts := _create_winlu_tileset()
		tilemap.tile_set = ts
		# Build the hub layout
		builder = HubShipBuilderScript.new()
		builder.tilemap = tilemap
		add_child(builder)
		builder._build_hub_layout()

	# Wire camera to follow player
	if camera_rig and player and camera_rig.has_method("set_follow_target"):
		camera_rig.set_follow_target(player)


func _create_winlu_tileset() -> TileSet:
	## Create a TileSet with Winlu tileset PNGs as atlas sources.
	## Source 0: A2 (floors), Source 1: A4 (walls), Sources 2-5: B-E (details)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var sources := [
		{"path": "res://assets/tilesets/winlu/tilesets/Spacestation_Inside_A2.png", "cols": 16, "rows": 12},
		{"path": "res://assets/tilesets/winlu/tilesets/Spacestation_Inside_A4.png", "cols": 16, "rows": 15},
		{"path": "res://assets/tilesets/winlu/tilesets/Spacestation_Inside_B.png", "cols": 16, "rows": 16},
		{"path": "res://assets/tilesets/winlu/tilesets/Spacestation_Inside_C.png", "cols": 16, "rows": 16},
		{"path": "res://assets/tilesets/winlu/tilesets/Spacestation_Inside_D.png", "cols": 16, "rows": 16},
		{"path": "res://assets/tilesets/winlu/tilesets/Spacestation_Inside_E.png", "cols": 16, "rows": 16},
	]

	for i in range(sources.size()):
		var src_info: Dictionary = sources[i]
		var tex: Texture2D = load(src_info["path"]) as Texture2D
		if tex == null:
			push_warning("Could not load tileset texture: " + src_info["path"])
			continue

		var atlas := TileSetAtlasSource.new()
		atlas.texture = tex
		atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

		# Create tiles for each cell in the atlas
		for col in range(src_info["cols"]):
			for row in range(src_info["rows"]):
				var coords := Vector2i(col, row)
				atlas.create_tile(coords)

		ts.add_source(atlas, i)

	return ts
