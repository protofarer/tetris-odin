package game

import "core:fmt"
import "core:log"
import sa "core:container/small_array"
import rl "vendor:raylib"

pr :: fmt.println
prf :: fmt.printfln

Void :: struct{}
Vec2 :: [2]f32
Vec2i :: [2]i32
Position :: Vec2i

PIXEL_WINDOW_HEIGHT :: 180
PLAYFIELD_BLOCK_H :: 18
PLAYFIELD_BLOCK_W :: 10
PLAYFIELD_BORDER_THICKNESS :: 10
BLOCK_PIXEL_SIZE :: PIXEL_WINDOW_HEIGHT / PLAYFIELD_BLOCK_H

INITIAL_FALL_INTERVAL :: 1 // sec

WINDOW_W :: 720
WINDOW_H :: 720
TICK_RATE :: 60

Game_Memory :: struct {
	player: Entity,
	game_state: Game_State,
	resman: ^Resource_Manager,
	debug: bool,
	tile_index: Tile_Index,
	block_render_data: [dynamic]Block_Render_Data,
	fall_timer: Timer,
	fall_y: i32,
	fall_interval: f32,
	input_delay: Timer,
	tetramino: Tetramino,
}

Block_Render_Data :: struct {
	x,y: f32,
	w,h: f32,
	color: rl.Color,
}

Tile_Index :: struct {
	tiles: [PLAYFIELD_BLOCK_H][PLAYFIELD_BLOCK_W]Tetramino_Type
}

Entity :: struct {
	pos: Position,
	size: Vec2,
	rotation: f32,
	color: rl.Color,
	texture_id: Texture_ID,
}

g: ^Game_Memory

Game_State :: enum {
	Play,
	Exit,
}

game_camera :: proc() -> rl.Camera2D {
	if g == nil do log.error("game_camera: invalid state, Game_Memory nil")
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT,
		target = {},
		offset = {},
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

interval_count := 1

// TODO: clear g.tetramino upon lockdown
spawn_tetramino :: proc(type: Tetramino_Type, layout_pos: Position = {0,0}) {
	if g.tetramino != {} {
		log.error("Cannot spawn tetramino when one currently exists")
		return
	}
	t := Tetramino{
		type = type,
		layout = get_layout(type, 0),
	}
	g.tetramino = t
}

// get tile and check OOB
get_tile :: proc(x: i32, y: i32) -> (Tetramino_Type, bool) {
	if x < 0 || x >= PLAYFIELD_BLOCK_W || y < 0 || y >= PLAYFIELD_BLOCK_H {
		return .None, false
	}
	return g.tile_index.tiles[y][x], true
}

update :: proc() {
	process_input()
	// TODO: rename to appropriate nomenclature, check for collision before moving
	// WARN: unsure to do fall and input in diff frames... if in same frame, then weird diagonal moves are possible

	old_tetra_layout_field_position := g.tetramino.layout_field_position

	// Mutated tetra blocks from input and fall
	new_tetramino_positions: sa.Small_Array(4, Position)
	for row, layout_local_y in g.tetramino.layout {
		for val, layout_local_x in row {
			if val != 0 {
				sa.append(
					&new_tetramino_positions, 
					Position{
						g.tetramino.layout_field_position.x + i32(layout_local_x), 
						g.tetramino.layout_field_position.y + i32(layout_local_y)
					}
				)
			}
		}
	}

	// Check if can move in x
	if g.tetramino.intended_relative_position != {} {
		can_move_x := true
		for pos in sa.slice(&new_tetramino_positions) {
			intended_x := pos.x + g.tetramino.intended_relative_position.x
			if tetra_type, in_bounds := get_tile(intended_x, i32(pos.y)); !in_bounds || tetra_type != .None {
				can_move_x = false
				break
			}
		}
		if can_move_x {
			// move layout in x
			g.tetramino.layout_field_position.x += g.tetramino.intended_relative_position.x
		}
		g.tetramino.intended_relative_position = {}
	}

	// Check if can fall
	if process_timer(&g.fall_timer) {
		// check next down position for collision: block or ground
		is_locked := false
		for &pos in sa.slice(&new_tetramino_positions) {
			tetra_type, in_bounds := get_tile(pos.x, pos.y + 1)
			if !in_bounds || tetra_type != .None {
				// locked: hit bottom or a locked block below
				// TODO: next_tetra routine: preview, spawn, eval_line_clear
				is_locked = true
			} 
		}
		if !is_locked {
			// fall
			g.tetramino.layout_field_position.y += 1
		}
		interval_count += 1 // tmp
	}

	// move tetra based on layout_field_pos delta
	d_tetra_layout_field_position := g.tetramino.layout_field_position - old_tetra_layout_field_position
	for &pos in sa.slice(&new_tetramino_positions) {
		pos += d_tetra_layout_field_position
	}

	// tmp
	if interval_count % 4 == 0 {
		increase_fall_rate()
		interval_count += 1
	}

	clear(&g.block_render_data)
	for row, field_y in g.tile_index.tiles {
		for block_type, field_x in row {

			// tetramino data
			is_occupied_by_tetra := false
			for tetra_field_pos in sa.slice(&new_tetramino_positions) {
				if tetra_field_pos.y == i32(field_y) && tetra_field_pos.x == i32(field_x) {
					append(&g.block_render_data, Block_Render_Data{
						x = PLAYFIELD_BORDER_THICKNESS + f32(field_x) * BLOCK_PIXEL_SIZE,
						y = f32(field_y) * BLOCK_PIXEL_SIZE,
						w = BLOCK_PIXEL_SIZE,
						h = BLOCK_PIXEL_SIZE,
						color = init_block(g.tetramino.type),
					})
					is_occupied_by_tetra = true
				}
			} 
			if is_occupied_by_tetra do continue

			// playfield data
			if block_type != .None {
				append(&g.block_render_data, Block_Render_Data{
					x = PLAYFIELD_BORDER_THICKNESS + f32(field_x) * BLOCK_PIXEL_SIZE,
					y = f32(field_y) * BLOCK_PIXEL_SIZE,
					w = BLOCK_PIXEL_SIZE,
					h = BLOCK_PIXEL_SIZE,
					color = init_block(block_type),
				})
			}
		}
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.GRAY)

	rl.BeginMode2D(game_camera())
	rl.DrawRectangle(0,0,PLAYFIELD_BORDER_THICKNESS, WINDOW_H, rl.DARKGRAY)
	rl.DrawRectangle(
		PLAYFIELD_BORDER_THICKNESS + PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE, 0,
		PLAYFIELD_BORDER_THICKNESS, WINDOW_H, rl.DARKGRAY
	)
	for brd in g.block_render_data {
		rl.DrawRectangleLinesEx({brd.x ,brd.y, brd.w, brd.h}, 1, rl.BLACK)
		rl.DrawRectangleV({brd.x+1, brd.y+1}, {brd.w-2, brd.h-2}, brd.color)
	}
	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())
		rl.DrawText(fmt.ctprintf("player_pos: %v", g.player.pos), 5, 5, 10, rl.WHITE)
	rl.EndMode2D()

	rl.EndDrawing()
}

Input :: enum {
	Down,
	Left,
	Right,
	Toggle_Music,
	Toggle_Preview,
	Exit,
	Toggle_Debug,
	Rotate_CCW,
	Rotate_CW,
}

// Map input to keys, make a table

Input_Set :: bit_set[Input]

Input_Map_Entry :: struct {
	input: Input,
	key: rl.KeyboardKey
}

input_map := [?]Input_Map_Entry{
	{.Toggle_Debug, .GRAVE},
	{.Down, .DOWN},
	{.Left, .LEFT},
	{.Right, .RIGHT},
	{.Rotate_CCW, .Z},
	{.Rotate_CW, .X},
	{.Toggle_Music, .M},
	{.Toggle_Preview, .P},
	{.Exit, .ESCAPE},
}

// when input pressed (and timer not running), start timer
// when input pressed and timer running, dont input
process_input :: proc() {
	if g.input_delay.state == .Inactive {
		start_timer(&g.input_delay)
	}
	process_timer(&g.input_delay)

	// Read input
	input: Input_Set
	for entry in input_map {
		switch entry.input {
		case .Toggle_Debug, .Toggle_Music, .Toggle_Preview, .Exit:
			if rl.IsKeyPressed(entry.key) {
				input += {entry.input}
			}
		case .Left, .Right, .Down:
			// check for input delay, could do this below but just hack it
			if rl.IsKeyDown(entry.key) && is_timer_done(g.input_delay) {
				input += {entry.input}
				restart_timer(&g.input_delay)
			}
		case .Rotate_CCW, .Rotate_CW:
			if rl.IsKeyPressed(entry.key) && is_timer_done(g.input_delay) {
				input += {entry.input}
				restart_timer(&g.input_delay)
			}
		}
	}

	// Apply input
	if .Left in input {
		g.tetramino.intended_relative_position.x = -1
	} else if .Right in input {
		g.tetramino.intended_relative_position.x = 1
	}

	if .Rotate_CCW in input {
		tetramino_next_layout()
	} else if .Rotate_CW in input {
		tetramino_previous_layout()

	}
}
 
// Run once: allocate, set global variable immutable values
setup :: proc() {
	context.logger = log.create_console_logger(nil, {
        // .Level,
        // .Terminal_Color,
        // .Short_File_Path,
        // .Line,
        // .Procedure,
        .Time,
	})

	resman := new(Resource_Manager)
	setup_resource_manager(resman)
	load_all_assets(resman)
	init_layout_tables()

	g = new(Game_Memory)
	g^ = Game_Memory {
		resman = resman,
	}
}
// clear collections, set initial values
init :: proc() {
	g.game_state = .Play
	g.debug = false

	clear_playfield()

	// for y in 0..<PLAYFIELD_BLOCK_H {
	// 	for x in 0..<PLAYFIELD_BLOCK_W {
	// 		if ((y + 1) * PLAYFIELD_BLOCK_W + x) % 3 == 0 {
	// 			g.tile_index.tiles[y][x] = .L
	// 		}
	// 	}
	// }

	g.input_delay = create_timer(0.1, .One_Shot, 1, "input_delay")

	g.fall_interval = INITIAL_FALL_INTERVAL
	g.fall_y = 0
	g.fall_timer = create_timer(INITIAL_FALL_INTERVAL, .Loop, 0, "fall")
	start_timer(&g.fall_timer)
}

increase_fall_rate :: proc() {
	// get remaining an tack onto timer for smooth transition
	dt := f32(g.fall_timer.remaining)
	g.fall_interval = max(g.fall_interval - 0.18, 0.1)
	pr("new interval", g.fall_interval)
	g.fall_timer = create_timer(g.fall_interval, .Loop, 0, "fall")
	g.fall_timer.accum += dt
	start_timer(&g.fall_timer)
}

draw_sprite :: proc(texture_id: Texture_ID, pos: Position, size: Vec2, rotation: f32 = 0, scale: f32 = 1, tint: rl.Color = rl.WHITE) {
	tex := get_texture(texture_id)
	src_rect := rl.Rectangle {
		0, 0, f32(tex.width), f32(tex.height),
	}
	dst_rect := rl.Rectangle {
		f32(pos.x), f32(pos.y), size.x, size.y,
	}
	rl.DrawTexturePro(tex, src_rect, dst_rect, {}, rotation, tint)
}

@(export)
game_update :: proc() {
	update()
	draw()
	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_W, WINDOW_H, "Odin Gamejam Template")
	rl.SetWindowPosition(500, 250)
	rl.SetTargetFPS(60)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	log.info("Initializing game...")
	setup() // run once
	init() // run after setup, then on reset
	spawn_tetramino(.T, {})

	game_hot_reloaded(g)
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			return false
		}
	}

	return g.game_state != .Exit
}

@(export)
game_shutdown :: proc() {
	free(g)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.R)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}

game_reset :: proc() {
	init()
}

aabb_intersects :: proc(a_x, a_y, a_w, a_h: f32, b_x, b_y, b_w, b_h: f32) -> bool {
    return !(a_x + a_w < b_x ||
           b_x + b_w < a_x ||
           a_y + a_h < b_y ||
           b_y + b_h < a_y)
}

Texture_ID :: enum {
    Player,
}

Sound_ID :: enum { 
    Powerup,
}

play_sound :: proc(id: Sound_ID) {
    rl.PlaySound(get_sound(id))
}

is_sound_playing :: proc(id: Sound_ID) -> bool {
    return rl.IsSoundPlaying(get_sound(id))
}

init_block :: proc(type: Tetramino_Type) -> rl.Color {
	color: rl.Color
	switch type {
	case .None:
		color = rl.BLANK
	case .I:
		color = rl.YELLOW
	case .J:
		color = rl.PINK
	case .L:
		color = rl.PURPLE
	case .Z:
		color = rl.ORANGE
	case .S:
		color = rl.YELLOW
	case .T:
		color = rl.BLUE
	case .O:
		color = rl.GREEN
	}
	return color
}

clear_playfield :: proc() {
	for y in 0..<PLAYFIELD_BLOCK_H {
		for x in 0..<PLAYFIELD_BLOCK_W {
			g.tile_index.tiles[y][x] = .None
		}
	}
}
