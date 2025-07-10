package game

import "core:fmt"
import "core:log"
import rl "vendor:raylib"
import sa "core:container/small_array"

pr :: fmt.println
prf :: fmt.printfln

Void :: struct{}
Vec2 :: [2]f32
Vec2i :: [2]i32
Position :: Vec2i

BACKGROUND_COLOR :: rl.LIGHTGRAY
PIXEL_WINDOW_HEIGHT :: 180
PLAYFIELD_BLOCK_H :: 18
PLAYFIELD_BLOCK_W :: 10
PLAYFIELD_BORDER_THICKNESS :: 10
BLOCK_PIXEL_SIZE :: PIXEL_WINDOW_HEIGHT / PLAYFIELD_BLOCK_H

INITIAL_FALL_INTERVAL :: 1 // sec

WINDOW_W :: 720
WINDOW_H :: 720
TICK_RATE :: 60

DAS_FRAMES :: 23
ARR_FRAMES :: 9 // TODO: replace delay_timer
ARE_CLEAR_FRAMES :: 93
ARE_FRAMES :: 2 // TODO: invis for 1st frame after spawning

LINE_CLEAR_ANIMATION_FRAME_INTERVAL :: 10
LINE_CLEAR_FLASH_COLOR :: rl.GRAY
// frames per row
LEVEL_DROP_RATES := [?]i32{
	53,
	49,
	45,
	41,
	37,
	33,
	28,
	22,
	17,
	11,
	 10,
	 9,
	 8,
	 7,
	 6,
	 6,
	 5,
	 5,
	 4,
	 4,
	 3,
}
SUPER_DROP_RATE :: 3

POINTS_TABLE := [?]i32{
	40,		// single
	100,	// double
	300,	// triple
	1200	// tetris
}

LINES_PER_LEVEL :: 10

Game_Memory :: struct {
	game_state: Game_State,
	resman: ^Resource_Manager,
	debug: bool,

	playfield: Playfield,
	tetramino: Tetramino,
	level: i32,
	score: i32,

	block_render_data: sa.Small_Array(PLAYFIELD_BLOCK_W * PLAYFIELD_BLOCK_H, Block_Render_Data),
	input_delay: Timer,
	input_repeat: Timer,
	input: Input_Set,

	fall_frames: i32,

	das: bool, // Delayed Auto Shift
	das_frames: i32,

	lines_just_cleared_y_positions: sa.Small_Array(PLAYFIELD_BLOCK_H, i32),
	show_lines_cleared_flash: bool,

	lines_cleared_accum: i32,

	// entry_frame_count: i32, // entry delay aka ARE
	// entry_frame_total: i32,
	entry_delay_timer: Timer,

	level_drop_rate: i32,
}

Block_Render_Data :: struct {
	x,y: f32,
	w,h: f32,
	color: rl.Color,
}

Playfield :: struct {
	blocks: [PLAYFIELD_BLOCK_H][PLAYFIELD_BLOCK_W]Tetramino_Type
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

spawn_tetramino :: proc(type: Tetramino_Type, layout_pos: Position = {0,0}) {
	if g.tetramino.type != .None {
		log.error("Cannot spawn tetramino when one currently exists")
		return
	}
	t := Tetramino{
		type = type,
		layout = get_layout(type, 0),
		layout_field_position = {3,0},
	}
	g.tetramino = t
	g.fall_frames = 0 // reset fall "timer"
}

// get tile and check OOB
get_playfield_block :: proc(x: i32, y: i32) -> (Tetramino_Type, bool) {
	if x < 0 || x >= PLAYFIELD_BLOCK_W || y < 0 || y >= PLAYFIELD_BLOCK_H {
		return .None, false
	}
	return g.playfield.blocks[y][x], true
}

// Returns 4 blocks as a rule, otherwise remains a usable zero valued array
get_tetramino_field_positions :: proc(layout: Tetramino_Layout, layout_field_position: Position) -> [TETRAMINO_BLOCKS_PER_LAYOUT]Position {
	idx := 0
	new_tetramino_positions: [TETRAMINO_BLOCKS_PER_LAYOUT]Position
	for row, layout_local_y in layout {
		for val, layout_local_x in row {
			if val != 0 {
				new_tetramino_positions[idx] = Position{
						layout_field_position.x + i32(layout_local_x), 
						layout_field_position.y + i32(layout_local_y)
					}
				idx += 1
			}
		}
	}
	return new_tetramino_positions
}

update :: proc() {
	// TODO: rename to appropriate nomenclature, check for collision before moving
	// WARN: unsure to do fall and input in diff frames... if in same frame, then weird diagonal moves are possible

	input: Input_Set
	process_input(&input)

	// CSDR
	// if g.tetramino != {} {
	// 	update_tetramino()
	// }

	old_tetra_positions := get_tetramino_field_positions(g.tetramino.layout, g.tetramino.layout_field_position)

	intended_move_x: i8
	intended_rotation: i8
	switch {
	case .Left in input:
		intended_move_x = -1
	case .Right in input:
		intended_move_x = 1
	case .Rotate_CCW in input:
		intended_rotation = -1
	case .Rotate_CW in input:
		intended_rotation = 1
	case:
		intended_move_x = 0
		intended_rotation = 0
	}

	// Check if can move in x
	if intended_move_x != 0 {
		can_move_x := true
		for pos in old_tetra_positions {
			intended_x := pos.x + i32(intended_move_x)
			if tetra_type, in_bounds := get_playfield_block(intended_x, i32(pos.y)); !in_bounds || tetra_type != .None {
				can_move_x = false
				break
			}
		}
		if can_move_x {
			g.tetramino.layout_field_position.x += i32(intended_move_x)
		}
	}

	// Check if can rotate
	if intended_rotation != 0 {
		intended_layout: Tetramino_Layout
		intended_layout_idx: int
		if intended_rotation == 1 {
			intended_layout, intended_layout_idx = get_next_layout(g.tetramino) 
		} else if intended_rotation == -1 {
			intended_layout, intended_layout_idx = get_previous_layout(g.tetramino)
		} else {
			unreachable()
		}

		intended_positions := get_tetramino_field_positions(intended_layout, g.tetramino.layout_field_position)
		can_rotate := true
		for intended_position in intended_positions {
			if tetra_type, in_bounds := get_playfield_block(intended_position.x, intended_position.y); !in_bounds || tetra_type != .None {
				can_rotate = false
				break
			}
		}

		if can_rotate {
			g.tetramino.layout = intended_layout
			g.tetramino.layout_idx = intended_layout_idx
		}
	}

	// Drop
	drop_rate := .Down in input ? SUPER_DROP_RATE : g.level_drop_rate
	if g.fall_frames < drop_rate {
		g.fall_frames += 1
	} else {
		// check next down position for collision: block or ground
		is_locked := false
		for pos in old_tetra_positions {
			tetra_type, in_bounds := get_playfield_block(pos.x, pos.y + 1)
			if !in_bounds || tetra_type != .None {
				is_locked = true
				break
			} 
		}
		if is_locked {
			// locked: hit bottom or a locked block below

			// create blocks at tetra locked positions
			tetra_positions := get_tetramino_field_positions(g.tetramino.layout, g.tetramino.layout_field_position)
			for pos in tetra_positions {
				set_playfield_block(pos.x, pos.y, g.tetramino.type)
			}

			// null g.tetra
			// NOTE: this zeroes out the layout, thus no blocks to operate on (or render!)
			g.tetramino = {
				type = .None
			}

			y_positions_cleared := eval_lines_cleared()
			n_lines_cleared := i32(sa.len(y_positions_cleared))
			set_timer_duration(&g.entry_delay_timer, n_lines_cleared > 0 ? ARE_CLEAR_FRAMES : ARE_FRAMES)
			restart_timer(&g.entry_delay_timer)
			g.lines_cleared_accum += n_lines_cleared
			g.lines_just_cleared_y_positions = y_positions_cleared

			// TODO: lines cleared animation
			// toggle show_blocks_cleared bool for all cleared blocks
			// use y_positions_cleared -> store in global
			// TODO: remove lines

			// update score
			if n_lines_cleared > 0 {
				g.score += calc_points(g.level, n_lines_cleared)

				if should_level_increase() {
					g.level += 1
					g.level_drop_rate = get_current_frames_per_row(LEVEL_DROP_RATES[:], g.level)
					// TODO: increase speed
				}
			}

			// TODO: randomizer and preview block

		} else {
			// fall
			g.tetramino.layout_field_position.y += 1
		}
		g.fall_frames = 0
	}


	// locked interlude processing
	if g.tetramino.type == .None  {
		// TODO: do on scene init
		if is_timer_done(g.entry_delay_timer) {
			reset_timer(&g.entry_delay_timer)

			// shift playfield down
			for y_to_clear in sa.slice(&g.lines_just_cleared_y_positions) {
				// cleared_y_positions naturally ordered correctly
				// starting from cleared_y_position - 1, copy into row below
				for y := y_to_clear; y >= 1; y -= 1 {
					g.playfield.blocks[y] = g.playfield.blocks[y-1]
				}
			}

			if sa.len(g.lines_just_cleared_y_positions) > 0 {
				sa.clear(&g.lines_just_cleared_y_positions)
				g.show_lines_cleared_flash = false
			}
			// update next preview (randomizer)
			// spawn preview block
			spawn_tetramino(.T)

			return
		}
		// animate lines_cleared state
		if int(get_timer_accum(g.entry_delay_timer)) % LINE_CLEAR_ANIMATION_FRAME_INTERVAL == 0 {
			g.show_lines_cleared_flash = !g.show_lines_cleared_flash
		}
		process_timer(&g.entry_delay_timer)
	}

	// move new tetra based on layout_field_pos delta
	new_tetramino_positions := get_tetramino_field_positions(g.tetramino.layout, g.tetramino.layout_field_position)

	sa.clear(&g.block_render_data)
	for row, field_y in g.playfield.blocks {
		for block_type, field_x in row {

			// tetramino data
			if g.tetramino.type != .None {
				is_occupied_by_tetra := false
				for tetra_field_pos in new_tetramino_positions {
					if tetra_field_pos.y == i32(field_y) && tetra_field_pos.x == i32(field_x) {
						sa.append(&g.block_render_data, Block_Render_Data{
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
			}

			// playfield data and conditional render for animating cleared lines
			if block_type != .None {
				is_block_in_cleared_row := false
				for y in sa.slice(&g.lines_just_cleared_y_positions) {
					if i32(field_y) == y {
						is_block_in_cleared_row = true
						break
					}
				}

				if !is_block_in_cleared_row || (is_block_in_cleared_row && g.show_lines_cleared_flash) {
					sa.append(&g.block_render_data, Block_Render_Data{
						x = PLAYFIELD_BORDER_THICKNESS + f32(field_x) * BLOCK_PIXEL_SIZE,
						y = f32(field_y) * BLOCK_PIXEL_SIZE,
						w = BLOCK_PIXEL_SIZE,
						h = BLOCK_PIXEL_SIZE,
						color = init_block(block_type),
					})
				} else if is_block_in_cleared_row && !g.show_lines_cleared_flash {
					sa.append(&g.block_render_data, Block_Render_Data{
						x = PLAYFIELD_BORDER_THICKNESS + f32(field_x) * BLOCK_PIXEL_SIZE,
						y = f32(field_y) * BLOCK_PIXEL_SIZE,
						w = BLOCK_PIXEL_SIZE,
						h = BLOCK_PIXEL_SIZE,
						color = LINE_CLEAR_FLASH_COLOR,
					})
				}
			}
		}
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(BACKGROUND_COLOR)

	rl.BeginMode2D(game_camera())
	rl.DrawRectangle(0,0,PLAYFIELD_BORDER_THICKNESS, WINDOW_H, rl.DARKGRAY)
	rl.DrawRectangle(
		PLAYFIELD_BORDER_THICKNESS + PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE, 0,
		PLAYFIELD_BORDER_THICKNESS, WINDOW_H, rl.DARKGRAY
	)
	for brd in sa.slice(&g.block_render_data) {
			rl.DrawRectangleV({brd.x+1, brd.y+1}, {brd.w-2, brd.h-2}, brd.color)
		if brd.color == LINE_CLEAR_FLASH_COLOR {
			rl.DrawRectangleLinesEx({brd.x ,brd.y, brd.w, brd.h}, 1, brd.color)
		} else {
			rl.DrawRectangleLinesEx({brd.x ,brd.y, brd.w, brd.h}, 1, rl.BLACK)
		}
	}

	if g.debug {
		for x in 0..<PLAYFIELD_BLOCK_W+1 {
			for y in 0..<PLAYFIELD_BLOCK_H+1 {
				rl.DrawLine(i32(x * BLOCK_PIXEL_SIZE + PLAYFIELD_BORDER_THICKNESS), 0, i32(x*BLOCK_PIXEL_SIZE +  PLAYFIELD_BORDER_THICKNESS), PLAYFIELD_BLOCK_H * BLOCK_PIXEL_SIZE, rl.BLUE)
				rl.DrawLine( PLAYFIELD_BORDER_THICKNESS, i32(y * BLOCK_PIXEL_SIZE), PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE + PLAYFIELD_BORDER_THICKNESS, i32(y*BLOCK_PIXEL_SIZE), rl.BLUE)
			}
		}
	}
	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())
		rl.DrawText(fmt.ctprintf("layout_pos: %v", g.tetramino.layout_field_position), 5, 5, 10, rl.WHITE)
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

process_input :: proc(input: ^Input_Set) {
	// Read input
	for entry in input_map {
		switch entry.input {
		case .Toggle_Debug, .Toggle_Music, .Toggle_Preview, .Exit:
			if rl.IsKeyPressed(entry.key) {
				input^ += {entry.input}
			}

		case .Left, .Right:
			// check for input delay, could do this below but just hack it
			if rl.IsKeyDown(entry.key) {
				process_timer(&g.input_delay)
				process_timer(&g.input_repeat)

				// Kickoff input delay timer
				if g.input_delay.state == .Inactive && g.input_repeat.state != .Running {
					input^ += {entry.input}
					restart_timer(&g.input_delay)
				}

				// Kickoff input repeat timer, apply input once
				if is_timer_done(g.input_delay) && g.input_repeat.state == .Inactive {
					input^ += {entry.input}
					start_timer(&g.input_repeat)
				}

				// Apply repeat input
				if is_timer_done(g.input_repeat) {
					input^ += {entry.input}
					restart_timer(&g.input_repeat)
				}
			}
			if rl.IsKeyReleased(entry.key) {
				reset_timer(&g.input_delay)
				reset_timer(&g.input_repeat)
			}

		// Down input is a flag, toggling super gravity
		case .Down:
			if rl.IsKeyDown(entry.key) {
				input^ += {entry.input}
			}
		case .Rotate_CCW, .Rotate_CW:
			if rl.IsKeyPressed(entry.key) {
				input^ += {entry.input}
			}
		}
	}

	// Apply some inputs here
	if .Toggle_Debug in input do g.debug = !g.debug
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

	rl.InitAudioDevice()
	resman := new(Resource_Manager)
	setup_resource_manager(resman)
	load_all_assets(resman)
	init_layout_tables()

	g = new(Game_Memory)
	g^ = Game_Memory {
		resman = resman,
	}
	g.input_repeat = create_timer(ARR_FRAMES, .One_Shot, .Tick, 1, "input_repeat")
	g.input_delay = create_timer(DAS_FRAMES, .One_Shot, .Tick, 1, "input_delay")
	g.entry_delay_timer = create_timer(ARE_FRAMES, .One_Shot, .Tick, 1, "entry_delay")
}

// clear collections, set initial values
init :: proc() {
	g.game_state = .Play
	g.debug = false
	g.das = false
	g.das_frames = 0
	set_timer_duration(&g.entry_delay_timer, ARE_FRAMES)
	reset_timer(&g.entry_delay_timer)
	g.tetramino = {}
	g.score = 0
	g.level = 0
	g.level_drop_rate = get_current_frames_per_row(LEVEL_DROP_RATES[:], g.level)
	g.fall_frames = 0
	g.show_lines_cleared_flash = false
	g.lines_cleared_accum = 0
	reset_timer(&g.input_delay)
	reset_timer(&g.input_repeat)

	sa.clear(&g.lines_just_cleared_y_positions)
	sa.clear(&g.block_render_data)
	clear_playfield()
	log.info("Initialization done.")
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
	rl.SetTargetFPS(TICK_RATE)
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
	return rl.IsKeyPressed(.F5) || rl.IsKeyPressed(.R)
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
			g.playfield.blocks[y][x] = .None
		}
	}
}

set_playfield_block :: proc(x: i32, y: i32, tetra_type: Tetramino_Type) {
	g.playfield.blocks[y][x] = tetra_type
}

get_current_frames_per_row :: proc(table: []i32, level: i32) -> i32 {
	return table[level]
}

calc_points :: proc(level: i32, n_lines_cleared: i32) -> i32 {
	idx: int
	if n_lines_cleared > 3 {
		idx = 3
	} else {
		idx = int(n_lines_cleared) - 1
	}
	return POINTS_TABLE[idx] * (level + 1)
}

should_level_increase :: proc() -> bool {
	if g.lines_cleared_accum > g.level * LINES_PER_LEVEL && g.lines_cleared_accum % LINES_PER_LEVEL == 0 {
		return true
	}
	return false
}

eval_lines_cleared :: proc() -> sa.Small_Array(PLAYFIELD_BLOCK_H, i32) {
	y_positions_cleared: sa.Small_Array(PLAYFIELD_BLOCK_H, i32)
	for row, y in g.playfield.blocks {
		is_continuous_blocks := true
		for val in row {
			if val == .None {
				is_continuous_blocks = false
				break
			}
		}
		if is_continuous_blocks {
			sa.append(&y_positions_cleared, i32(y))
		}
	}
	return y_positions_cleared
}
