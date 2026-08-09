extends Node2D
## Zoo map controller — manages the TileMapLayer and entity placement.
## Generates tileset + paints zoo layout programmatically from placeholder PNGs.

const TILE_SIZE := 64
const MAP_WIDTH := 24
const MAP_HEIGHT := 30

@onready var tile_map: TileMapLayer = $TileMapLayer

var _occupied_cells: Dictionary = {}  # Vector2i → entity_id
var _zone_overlays: Dictionary = {}  # zone_name → ColorRect
var _unlocked_zones: Dictionary = {}  # zone_name → bool

# Tile source IDs (assigned during tileset creation)
enum Tile { GRASS, GRASS2, PATH, WATER, FENCE, SAND, SNOW, SAVANNA }

# Zone definitions: name → Rect2i area on the grid
var zones: Dictionary = {
	"farm":     Rect2i(1, 1, 10, 7),
	"tropical": Rect2i(13, 1, 10, 7),
	"arctic":   Rect2i(1, 16, 10, 7),
	"savanna":  Rect2i(13, 16, 10, 7),
}

# Zone → base tile type
var _zone_tiles: Dictionary = {
	"farm":     Tile.GRASS,
	"tropical": Tile.SAND,
	"arctic":   Tile.SNOW,
	"savanna":  Tile.SAVANNA,
}


func _ready() -> void:
	_build_tileset()
	_paint_zoo_layout()
	_create_zone_overlays()


func _create_zone_overlays() -> void:
	for zone_name in zones:
		var rect: Rect2i = zones[zone_name]
		var overlay = ColorRect.new()
		overlay.name = "Overlay_%s" % zone_name
		overlay.color = Color(0.1, 0.1, 0.1, 0.6)
		overlay.position = Vector2(rect.position.x * TILE_SIZE, rect.position.y * TILE_SIZE)
		overlay.size = Vector2(rect.size.x * TILE_SIZE, rect.size.y * TILE_SIZE)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)
		_zone_overlays[zone_name] = overlay

		# Lock label centered on zone
		var lock_label = Label.new()
		lock_label.text = "🔒"
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock_label.add_theme_font_size_override("font_size", 32)
		lock_label.anchors_preset = Control.PRESET_CENTER
		lock_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		lock_label.grow_vertical = Control.GROW_DIRECTION_BOTH
		overlay.add_child(lock_label)

	# Farm starts unlocked
	unlock_zone("farm", false)


func unlock_zone(zone_name: String, animate: bool = true) -> void:
	if zone_name not in _zone_overlays:
		return
	if _unlocked_zones.get(zone_name, false):
		return

	_unlocked_zones[zone_name] = true
	var overlay: ColorRect = _zone_overlays[zone_name]

	if animate:
		var tween = create_tween()
		tween.tween_property(overlay, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_OUT)
		tween.tween_callback(overlay.queue_free)
		tween.tween_callback(func(): _zone_overlays.erase(zone_name))
	else:
		overlay.queue_free()
		_zone_overlays.erase(zone_name)


func is_zone_unlocked(zone_name: String) -> bool:
	return _unlocked_zones.get(zone_name, false)


func get_map_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE))


func get_zone_for_type(type_id: String) -> String:
	var cfg = Config.get_entity_config(type_id)
	return cfg.get("zone", "farm")


func get_first_free_cell(zone_name: String = "farm") -> Vector2i:
	var rect: Rect2i = zones.get(zone_name, zones["farm"])
	# Search inside the zone area (skip fence border)
	for y in range(rect.position.y + 1, rect.position.y + rect.size.y - 1):
		for x in range(rect.position.x + 1, rect.position.x + rect.size.x - 1):
			var cell = Vector2i(x, y)
			if cell not in _occupied_cells:
				return cell
	return Vector2i(-1, -1)


func occupy_cell(cell: Vector2i, entity_id: String) -> void:
	_occupied_cells[cell] = entity_id


func free_cell(cell: Vector2i) -> void:
	_occupied_cells.erase(cell)


func grid_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2, cell.y * TILE_SIZE + TILE_SIZE / 2)


## Inverse of grid_to_world. Used to tell the rhythm engine which cell the
## camera is looking at, so the voice cap can prefer the animals on screen.
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))


# --- Tileset & Layout Generation ---

func _build_tileset() -> void:
	var ts = TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var tile_files: Array[String] = [
		"res://assets/tiles/grass.png",
		"res://assets/tiles/grass2.png",
		"res://assets/tiles/path.png",
		"res://assets/tiles/water.png",
		"res://assets/tiles/fence.png",
		"res://assets/tiles/sand.png",
		"res://assets/tiles/snow.png",
		"res://assets/tiles/savanna.png",
	]

	for i in range(tile_files.size()):
		var source = TileSetAtlasSource.new()
		source.texture = load(tile_files[i])
		source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
		ts.add_source(source, i)
		source.create_tile(Vector2i(0, 0))

	tile_map.tile_set = ts


func _paint_zoo_layout() -> void:
	# Fill entire map with grass
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			_set_tile(x, y, Tile.GRASS if (x + y) % 3 != 0 else Tile.GRASS2)

	# Paint central paths (horizontal + vertical cross)
	for x in range(MAP_WIDTH):
		_set_tile(x, 9, Tile.PATH)
		_set_tile(x, 10, Tile.PATH)
		_set_tile(x, 14, Tile.PATH)
		_set_tile(x, 15, Tile.PATH)
	for y in range(MAP_HEIGHT):
		_set_tile(11, y, Tile.PATH)
		_set_tile(12, y, Tile.PATH)

	# Paint entrance path at bottom center
	for y in range(24, MAP_HEIGHT):
		_set_tile(11, y, Tile.PATH)
		_set_tile(12, y, Tile.PATH)

	# Water features (decorative ponds)
	for dx in range(3):
		for dy in range(3):
			_set_tile(5 + dx, 12 + dy, Tile.WATER)
			_set_tile(18 + dx, 12 + dy, Tile.WATER)

	# Paint zone areas
	for zone_name in zones:
		var rect: Rect2i = zones[zone_name]
		var base_tile: int = _zone_tiles[zone_name]

		# Fill zone interior with zone tile
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				_set_tile(x, y, base_tile)

		# Fence border around zone
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			_set_tile(x, rect.position.y, Tile.FENCE)
			_set_tile(x, rect.position.y + rect.size.y - 1, Tile.FENCE)
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			_set_tile(rect.position.x, y, Tile.FENCE)
			_set_tile(rect.position.x + rect.size.x - 1, y, Tile.FENCE)

		# Gate opening (2 tiles wide, bottom center of fence)
		var gate_x = rect.position.x + rect.size.x / 2
		_set_tile(gate_x, rect.position.y + rect.size.y - 1, Tile.PATH)
		_set_tile(gate_x - 1, rect.position.y + rect.size.y - 1, Tile.PATH)


func _set_tile(x: int, y: int, tile_id: int) -> void:
	tile_map.set_cell(Vector2i(x, y), tile_id, Vector2i(0, 0))
