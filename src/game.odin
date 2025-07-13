package game

import "core:fmt"
import "core:log"
import "core:math/rand"
import rl "vendor:raylib"
import sa "core:container/small_array"

pr :: fmt.println
prf :: fmt.printfln

Void :: struct{}
Vec2 :: [2]f32
Vec2i :: [2]i32
Position :: Vec2i

WINDOW_W :: 720
WINDOW_H :: 720
TICK_RATE :: 60

PIXEL_WINDOW_HEIGHT :: 180

BACKGROUND_COLOR :: rl.Color{142,142,142,255}

PLAYFIELD_BLOCK_H :: 18
PLAYFIELD_BLOCK_W :: 10
PLAYFIELD_BORDER_THICKNESS :: 10
BLOCK_PIXEL_SIZE :: PIXEL_WINDOW_HEIGHT / PLAYFIELD_BLOCK_H

PANEL_X :: PLAYFIELD_BORDER_THICKNESS * 2 + (PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE)
PANEL_Y :: 0
PANEL_WIDTH :: WINDOW_W - PANEL_X
PANEL_HEIGHT :: WINDOW_H

INITIAL_FALL_INTERVAL :: 1 // sec

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
	game_state: Game_State, // CSDR app_state
	resman: ^Resource_Manager,
	debug: bool,

	scene: Scene,
	next_scene: Maybe(Scene_Type),
}


Block_Render_Data :: struct {
	x,y: f32,
	w,h: f32,
	color: rl.Color,
	border_color: rl.Color,
	highlight_color: rl.Color,
}

Playfield :: struct {
	blocks: Playfield_Blocks
}

Playfield_Blocks :: [PLAYFIELD_BLOCK_H][PLAYFIELD_BLOCK_W]Tetramino_Type

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

Global_Input :: enum {
	Toggle_Debug,
	Exit,
}

GLOBAL_INPUT_MAP := [?]Input_Map_Entry(Global_Input){
	{.Toggle_Debug, .GRAVE},
	{.Exit, .ESCAPE},
}

update :: proc() {
	dt := rl.GetFrameTime()

	// Global Input
	input: bit_set[Global_Input]
	for entry in GLOBAL_INPUT_MAP {
		switch entry.input {
		case .Toggle_Debug, .Exit:
			if rl.IsKeyPressed(entry.key) {
				input += {entry.input}
			}
		}
	}
	if .Toggle_Debug in input {
		g.debug = !g.debug
		pr("toggle global debug")
	} else if .Exit in input {
		game_shutdown()
		game_shutdown_window()
	}

	update_scene(&g.scene, &g.next_scene, dt)

	if next, ok := g.next_scene.?; ok {
		transition_scene(next)
		g.next_scene = nil
	}
}

draw :: proc() {
	draw_scene(&g.scene)
}

draw_play_scene :: proc(s: ^Play_Scene) {
	rl.BeginDrawing()
	rl.ClearBackground(BACKGROUND_COLOR)

	tex_bg := get_texture(.Background)
	src := rl.Rectangle{0, 0, f32(tex_bg.width), f32(tex_bg.height)}
	dst := rl.Rectangle{0, 0, WINDOW_W, WINDOW_H}
	rl.DrawTexturePro(tex_bg, src, dst, {}, 0, rl.Color{147,210,255,255})

	rl.BeginMode2D(game_camera())

	// Borders
	rl.DrawRectangle(0,0,
		PLAYFIELD_BORDER_THICKNESS, WINDOW_H, 
		rl.GRAY
	)
	tex_border := get_texture(.Border)
	src_border := rl.Rectangle{0, 0, f32(tex_border.width), f32(tex_border.height)}
	dst_border := rl.Rectangle{0, 0, PLAYFIELD_BORDER_THICKNESS, PIXEL_WINDOW_HEIGHT}
	rl.DrawTexturePro(tex_border, src_border, dst_border, {}, 0, rl.RAYWHITE)

	rl.DrawRectangle(
		PLAYFIELD_BORDER_THICKNESS + PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE, 0,
		PLAYFIELD_BORDER_THICKNESS, WINDOW_H, 
		rl.GRAY
	)
	dst_border_2 := rl.Rectangle{
		PLAYFIELD_BORDER_THICKNESS + PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE, 
		0, 
		PLAYFIELD_BORDER_THICKNESS, 
		PIXEL_WINDOW_HEIGHT
	}
	rl.DrawTexturePro(tex_border, src_border, dst_border_2, {}, 0, rl.RAYWHITE)
	// rl.DrawRectangle(
	// 	PLAYFIELD_BORDER_THICKNESS + PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE, 0,
	// 	PLAYFIELD_BORDER_THICKNESS, WINDOW_H, rl.BLUE
	// )

	// Playfield + Tetra
	for brd in sa.slice(&s.block_render_data) {
		draw_block(brd.x, brd.y, brd.w, brd.h, brd.color, brd.border_color, brd.highlight_color)
	}

	// Panel
	rl.DrawRectangleV({PANEL_X, PANEL_Y}, {PANEL_WIDTH, PANEL_HEIGHT}, rl.Color{30,30,30, 128})

	SCORE_LABEL_POS :: Vec2i{PANEL_X + 5, 5}
	SCORE_VALUE_POS :: Vec2i{SCORE_LABEL_POS.x, SCORE_LABEL_POS.y + 15}

	score_rect := rl.Rectangle{f32(SCORE_LABEL_POS.x-3), f32(SCORE_LABEL_POS.y-3), 45, 30}
	rl.DrawRectangleRounded(score_rect, 0.1, 3, rl.WHITE)
	// DrawRectangleRounded(rec: Rectangle, roundness: f32, segments: c.int, color: Color)
	// rl.DrawRectangle(SCORE_LABEL_POS.x-3, SCORE_LABEL_POS.y-3, 45, 30, rl.WHITE)
	rl.DrawText("SCORE", SCORE_LABEL_POS.x, SCORE_LABEL_POS.y, 9, rl.BLACK)
	rl.DrawText(fmt.ctprint(s.score), SCORE_VALUE_POS.x, SCORE_VALUE_POS.y, 10, rl.BLACK)

	LEVEL_LABEL_POS :: Vec2i{PANEL_X + 5, 50}
	LEVEL_VALUE_POS :: Vec2i{LEVEL_LABEL_POS.x, LEVEL_LABEL_POS.y + 10}
	level_rect := rl.Rectangle{f32(LEVEL_LABEL_POS.x-3), f32(LEVEL_LABEL_POS.y-3), 45, 23}
	rl.DrawRectangleRounded(level_rect, 0.1, 3, rl.WHITE)
	// rl.DrawRectangle(LEVEL_LABEL_POS.x-3, LEVEL_LABEL_POS.y-3, 45, 23, rl.WHITE)
	rl.DrawText("LEVEL", LEVEL_LABEL_POS.x, LEVEL_LABEL_POS.y, 10, rl.BLACK)
	rl.DrawText(fmt.ctprint(s.level), LEVEL_VALUE_POS.x, LEVEL_VALUE_POS.y, 10, rl.BLACK)

	LINES_LABEL_POS :: Vec2i{PANEL_X + 5, 80}
	LINES_VALUE_POS :: Vec2i{LINES_LABEL_POS.x, LINES_LABEL_POS.y + 10}
	lines_rect := rl.Rectangle{f32(LINES_LABEL_POS.x-3), f32(LINES_LABEL_POS.y-3), 45, 23}
	rl.DrawRectangleRounded(lines_rect, 0.1, 3, rl.WHITE)
	// rl.DrawRectangle(LINES_LABEL_POS.x-3, LINES_LABEL_POS.y-3, 45, 23, rl.WHITE)
	rl.DrawText("LINES", LINES_LABEL_POS.x, LINES_LABEL_POS.y, 10, rl.BLACK)
	rl.DrawText(fmt.ctprint(s.lines_cleared_accum), LINES_VALUE_POS.x, LINES_VALUE_POS.y, 10, rl.BLACK)

	PREVIEW_BOX_POS :: Vec2{PANEL_X + 5, 110}
	PREVIEW_BOX_SIZE :: Vec2{50,50}
	preview_rect := rl.Rectangle{f32(PREVIEW_BOX_POS.x-3), f32(PREVIEW_BOX_POS.y-3), PREVIEW_BOX_SIZE.x, PREVIEW_BOX_SIZE.y}
	rl.DrawRectangleRounded(preview_rect, 0.1, 3, rl.WHITE)
	// rl.DrawRectangleV(PREVIEW_BOX_POS, PREVIEW_BOX_SIZE, rl.RAYWHITE)

	for row, y in s.preview_tetra.layout {
		for val, x in row {
			if val != 0 {
				draw_block(
					f32(PREVIEW_BOX_POS.x) + f32(x) * BLOCK_PIXEL_SIZE, 
					f32(PREVIEW_BOX_POS.y) + f32(y) * BLOCK_PIXEL_SIZE, 
					BLOCK_PIXEL_SIZE, 
					BLOCK_PIXEL_SIZE, 
					s.preview_tetra.color,
					rl.BLACK,
					rl.RAYWHITE,
				)
			}
		}
	}

	if s.is_game_over {
		y1 :i32 = 25
		r := rl.Rectangle{25-3, f32(y1)-3, 45, 45}
		// rl.DrawRectangleRoundedLines(r, 0.1, 3, rl.WHITE)
		rl.DrawRectangleRounded(r, 0.1, 3, rl.Color{255,255,255,192})

		rl.DrawText("GAME", 25, y1, 12, rl.BLACK)
		y1 += 10
		rl.DrawText("OVER", 25, y1, 12, rl.BLACK)
		y2 :i32= 75
		rl.DrawText("PLEASE ", 25, y2, 12, rl.BLACK)
		y2 += 10
		rl.DrawText("TRY", 25, y2, 12, rl.BLACK)
		y2 += 10
		rl.DrawText("AGAIN", 25, y2, 12, rl.BLACK)
		y2 += 15
		rl.DrawText("HIT ENTER", 25, y2, 12, rl.BLACK)
	}

	// Debug
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
		rl.DrawText(fmt.ctprintf("layout_pos: %v\nlevel_drop_rate: %v", s.tetramino.layout_field_position, s.level_drop_rate), 5, 5, 10, rl.WHITE)
	rl.EndMode2D()

	rl.EndDrawing()
}

Play_Input :: enum {
	Drop,
	Shift_Left,
	Shift_Right,
	Rotate_CCW,
	Rotate_CW,
	Toggle_Music,
	Toggle_Preview,
	Exit,
	Toggle_Debug,
	Goto_Menu,
}

Input_Map_Entry :: struct ($T: typeid) {
	input: T,
	key: rl.KeyboardKey
}

PLAY_INPUT_MAP := [?]Input_Map_Entry(Play_Input){
	{.Toggle_Debug, .GRAVE},
	{.Drop, .DOWN},
	{.Shift_Left, .LEFT},
	{.Shift_Right, .RIGHT},
	{.Rotate_CCW, .Z},
	{.Rotate_CW, .X},
	{.Drop, .S},
	{.Shift_Left, .A},
	{.Shift_Right, .D},
	{.Toggle_Music, .M},
	{.Toggle_Preview, .P},
	{.Exit, .ESCAPE},
	{.Goto_Menu, .ENTER}
}

process_input_play_scene :: proc(s: ^Play_Scene) -> bit_set[Play_Input] {
	input: bit_set[Play_Input]

	// Read input
	for entry in PLAY_INPUT_MAP {
		switch entry.input {
		case .Toggle_Debug, .Toggle_Music, .Toggle_Preview, .Exit, .Goto_Menu:
			if rl.IsKeyPressed(entry.key) {
				input += {entry.input}
			}

		case .Shift_Left, .Shift_Right, .Rotate_CCW, .Rotate_CW:
			delay_and_repeat_input(s, &input, entry.key, entry.input)

		// Down input is a flag, toggling super gravity
		case .Drop:
			if rl.IsKeyDown(entry.key) {
				input += {entry.input}
			}
		}
	}

	// tmp
	if rl.IsKeyPressed(.G) {
		s.is_game_over = true
	}

	if s.is_game_over && .Goto_Menu in input {
		pr("transition scene to menu")
		transition_scene(.Menu)
	}

	return input
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
}

// clear collections, set initial values
init :: proc() {
	g.game_state = .Play
	g.debug = false
	transition_scene(.Play)
}

init_menu_scene :: proc(s: ^Menu_Scene) {
	s.selected_game_type = .A
	s.selected_music_type = .A
	s.is_hard_mode_selected = false
}

init_play_scene :: proc(s: ^Play_Scene) {
	set_timer_duration(&s.entry_delay_timer, ARE_FRAMES)
	reset_timer(&s.entry_delay_timer)
	s.tetramino = {}
	s.score = 0
	s.level = 0
	s.level_drop_rate = get_current_frames_per_row(LEVEL_DROP_RATES[:], s.level)
	s.fall_frames = 0
	s.show_lines_cleared_flash = true
	s.lines_cleared_accum = 0
	reset_timer(&s.input_repeat_delay_timer)
	reset_timer(&s.input_repeat_timer)

	sa.clear(&s.lines_just_cleared_y_positions)
	sa.clear(&s.block_render_data)
	clear_playfield(s)
	log.info("Initialization done.")

	update_preview_tetra(s)
	starting_tetra_type := roll_start_game(s^)
	spawn_tetramino(starting_tetra_type, {}, s)
	s.input_repeat_timer = create_timer(ARR_FRAMES, .One_Shot, .Tick, 1, "input_repeat_timer")
	s.input_repeat_delay_timer = create_timer(DAS_FRAMES, .One_Shot, .Tick, 1, "input_repeat_delay_timer")
	s.entry_delay_timer = create_timer(ARE_FRAMES, .One_Shot, .Tick, 1, "entry_delay")
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

clear_playfield :: proc(s: ^Play_Scene) {
	for y in 0..<PLAYFIELD_BLOCK_H {
		for x in 0..<PLAYFIELD_BLOCK_W {
			s.playfield.blocks[y][x] = .None
		}
	}
}

set_playfield_block :: proc(s: ^Play_Scene, x: i32, y: i32, tetra_type: Tetramino_Type) {
	s.playfield.blocks[y][x] = tetra_type
}

get_current_frames_per_row :: proc(table: []i32, level: i32) -> i32 {
	return table[level]
}

calc_points :: proc(level: i32, n_lines_cleared: i32) -> i32 {
	if n_lines_cleared <= 3 {
		idx := int(n_lines_cleared) - 1
		return POINTS_TABLE[idx] * (level + 1)
	} else {
		return POINTS_TABLE[3] * (level + 1)
	} 
}

should_level_increase :: proc(lines_cleared_accum: i32, level: i32) -> bool {
	if (lines_cleared_accum >= (level + 1) * LINES_PER_LEVEL) {
		return true
	}
	return false
}

eval_lines_cleared :: proc(blocks: Playfield_Blocks) -> sa.Small_Array(PLAYFIELD_BLOCK_H, i32) {
	y_positions_cleared: sa.Small_Array(PLAYFIELD_BLOCK_H, i32)
	for row, y in blocks {
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

randomize_tetra_type :: proc(s: Play_Scene) -> Tetramino_Type {
	tetra_type := roll_eight()
	if tetra_type == .None || tetra_type == s.preview_tetra.type {
		tetra_type = roll_seven()
	}
	return tetra_type
}

START_TETRA_CHOICE := [?]Tetramino_Type{
	.I, .J, .L, .T
}

ALL_TETRA_CHOICE := [?]Tetramino_Type{
	.I, .J, .L, .T, .S, .Z, .O
}

// Can return .None
roll_eight :: proc() -> Tetramino_Type {
	return rand.choice_enum(Tetramino_Type)
}

// Always returns a tetra
roll_seven :: proc() -> Tetramino_Type {
	tetra_type := rand.choice(ALL_TETRA_CHOICE[:])
	return tetra_type
}

// never deals an S, Z or O as the first piece, to avoid a forced overhang (S,Z) and give flexibility (O)
roll_start_game :: proc(s: Play_Scene) -> Tetramino_Type {
	for {
		if t := rand.choice(START_TETRA_CHOICE[:]); t != s.preview_tetra.type {
			return t
		}
	}
}

draw_block :: proc(x,y,w,h: f32, fill_color, border_color: rl.Color, highlight_color: rl.Color) {
	draw_block_fill(x,y,w,h,fill_color,highlight_color)
	draw_block_border(x,y,w,h,border_color)
}

draw_block_fill :: proc(x, y, w, h: f32, fill_color: rl.Color, highlight_color: rl.Color) {
	// Body
	rl.DrawRectangleV({x+1, y+1}, {w-2, h-2}, fill_color)

	// Highlight
	rl.DrawPixel(i32(x+1), i32(y+1), highlight_color) // point

	rl.DrawRectangleV({x+2, y+2}, {2, 2}, highlight_color) // edge
	rl.DrawPixel(i32(x+2+1), i32(y+2+1), fill_color) // block out
}

draw_block_border :: proc(x, y, w, h: f32, color: rl.Color) {
		rl.DrawRectangleLinesEx({x ,y, w, h}, 1, color)
}

update_preview_tetra :: proc(s: ^Play_Scene) {
	tetra_type := randomize_tetra_type(s^)
	tetra: Tetramino
	init_tetra(&tetra, tetra_type)
	s.preview_tetra = tetra
}

init_tetra :: proc(tetra: ^Tetramino, type: Tetramino_Type) {
	tetra^ = Tetramino{
		type = type,
		layout = get_layout(type, 0),
		layout_field_position = {3,0},
		color = TETRA_COLORS[type],
	}
}

spawn_tetramino :: proc(type: Tetramino_Type, layout_pos: Position = {0,0}, play_scene: ^Play_Scene) {
	if play_scene.tetramino.type != .None {
		log.error("Cannot spawn tetramino when one currently exists")
		return
	}
	t: Tetramino
	init_tetra(&t, type)
	play_scene.tetramino = t
	play_scene.fall_frames = 0 // reset fall "timer"
}

// get tile and check OOB
get_playfield_block :: proc(x: i32, y: i32, blocks: Playfield_Blocks) -> (Tetramino_Type, bool) {
	if x < 0 || x >= PLAYFIELD_BLOCK_W || y < 0 || y >= PLAYFIELD_BLOCK_H {
		return .None, false
	}
	return blocks[y][x], true
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

delay_and_repeat_input :: proc(s: ^Play_Scene, input_set: ^bit_set[Play_Input], key: rl.KeyboardKey, input: Play_Input) {
	if rl.IsKeyDown(key) {
		process_timer(&s.input_repeat_delay_timer)
		process_timer(&s.input_repeat_timer)

		// Kickoff input delay timer
		if s.input_repeat_delay_timer.state == .Inactive && s.input_repeat_timer.state != .Running {
			input_set^ += {input}
			restart_timer(&s.input_repeat_delay_timer)
		}

		// Kickoff input repeat timer, apply input once
		if is_timer_done(s.input_repeat_delay_timer) && s.input_repeat_timer.state == .Inactive {
			input_set^ += {input}
			start_timer(&s.input_repeat_timer)
		}

		// Apply repeat input
		if is_timer_done(s.input_repeat_timer) {
			input_set^ += {input}
			restart_timer(&s.input_repeat_timer)
		}
	}
	if rl.IsKeyReleased(key) {
		reset_timer(&s.input_repeat_delay_timer)
		reset_timer(&s.input_repeat_timer)
	}
}

Scene_Type :: enum {
	Menu,
	Play,
}

Menu_Scene :: struct {
	selected_game_type: Game_Type,
	selected_music_type: Music_Type,
	is_hard_mode_selected: bool,
}

Game_Type :: enum { A, B }
Music_Type :: enum { A, B, C, D }

Play_Scene :: struct {
	playfield: Playfield,
	tetramino: Tetramino,
	level: i32,
	score: i32,

	block_render_data: sa.Small_Array(PLAYFIELD_BLOCK_W * PLAYFIELD_BLOCK_H, Block_Render_Data),
	input_repeat_delay_timer: Timer, // DAS
	input_repeat_timer: Timer, // ARR
	input: bit_set[Play_Input],

	fall_frames: i32,

	lines_just_cleared_y_positions: sa.Small_Array(PLAYFIELD_BLOCK_H, i32),
	show_lines_cleared_flash: bool,
	lines_cleared_accum: i32,
	entry_delay_timer: Timer, // ARE

	level_drop_rate: i32,

	// For randomizer, reroll if 1st roll results in same previous tetra
	previous_tetra_type: Tetramino_Type,
	preview_tetra: Tetramino,

	is_game_over: bool,
}

Scene :: union {
	Menu_Scene,
	Play_Scene,
}

update_scene :: proc(scene: ^Scene, next_scene: ^Maybe(Scene_Type), dt: f32) {
	switch &s in scene {
	case Play_Scene:
		update_play_scene(&s)
	case Menu_Scene:
		update_menu_scene(&s)
	}
}

draw_scene :: proc(scene: ^Scene) {
	switch &s in scene {
	case Play_Scene:
		draw_play_scene(&s)
	case Menu_Scene:
		draw_menu_scene(&s)
	}
}

draw_menu_scene :: proc(s: ^Menu_Scene) {
	rl.BeginDrawing()
	rl.ClearBackground(BACKGROUND_COLOR)

	rl.BeginMode2D(game_camera())
	rl.DrawText("Menu Scene", 10, 10, 11, rl.BLACK)

	gt := fmt.ctprintf("Game Type: %v", s.selected_game_type)
	rl.DrawText(gt, 10, 20, 11, rl.BLACK)

	mt := fmt.ctprintf("Music Type: %v", s.selected_music_type)
	rl.DrawText(mt, 10, 30, 11, rl.BLACK)

	rl.DrawText("SPACE TO START", 10, 50, 11, rl.BLACK)

	rl.EndMode2D()
	rl.EndDrawing()
}

update_play_scene :: proc(s: ^Play_Scene) {
	// TODO: rename to appropriate nomenclature, check for collision before moving
	// WARN: unsure to do fall and input in diff frames... if in same frame, then weird diagonal moves are possible

	input := process_input_play_scene(s)

	if s.is_game_over {
		return
	}

	// CSDR
	// if g.tetramino != {} {
	// 	update_tetramino()
	// }

	old_tetra_positions := get_tetramino_field_positions(s.tetramino.layout, s.tetramino.layout_field_position)

	if s.tetramino.type != .None {
		intended_move_x: i8
		intended_rotation: i8
		switch {
		case .Shift_Left in input:
			intended_move_x = -1
		case .Shift_Right in input:
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
				if tetra_type, in_bounds := get_playfield_block(intended_x, i32(pos.y), s.playfield.blocks); !in_bounds || tetra_type != .None {
					can_move_x = false
					break
				}
			}
			if can_move_x {
				s.tetramino.layout_field_position.x += i32(intended_move_x)
				play_sound(.Shift)
			}
		}

		// Check if can rotate
		if intended_rotation != 0 {
			intended_layout: Tetramino_Layout
			intended_layout_idx: int
			if intended_rotation == 1 {
				intended_layout, intended_layout_idx = get_next_layout(s.tetramino) 
			} else if intended_rotation == -1 {
				intended_layout, intended_layout_idx = get_previous_layout(s.tetramino)
			}

			intended_positions := get_tetramino_field_positions(intended_layout, s.tetramino.layout_field_position)
			can_rotate := true
			for intended_position in intended_positions {
				if tetra_type, in_bounds := get_playfield_block(intended_position.x, intended_position.y, s.playfield.blocks); !in_bounds || tetra_type != .None {
					can_rotate = false
					break
				}
			}

			if can_rotate {
				s.tetramino.layout = intended_layout
				s.tetramino.layout_idx = intended_layout_idx
				play_sound(.Rotate)
			}
		}

		// Drop
		drop_rate := .Drop in input ? SUPER_DROP_RATE : s.level_drop_rate
		if s.fall_frames < drop_rate {
			s.fall_frames += 1
		} else {
			// check next down position for collision: block or ground
			is_locked := false
			for pos in old_tetra_positions {
				tetra_type, in_bounds := get_playfield_block(pos.x, pos.y + 1, s.playfield.blocks)
				if !in_bounds || tetra_type != .None {
					is_locked = true
					break
				} 
			}
			if is_locked {
				// locked: set the tetra in place and associated events

				// create blocks at tetra locked positions
				tetra_positions := get_tetramino_field_positions(s.tetramino.layout, s.tetramino.layout_field_position)
				for pos in tetra_positions {
					set_playfield_block(s, pos.x, pos.y, s.tetramino.type)
				}

				s.previous_tetra_type = s.tetramino.type

				// NOTE: this zeroes out the layout, thus no blocks to operate on (or render!)
				// NOTE: other code keys off this value to signify no player controllable tetra on screen aka non-existent player tetra aka post-lock operations
				s.tetramino = {
					type = .None
				}

				y_positions_cleared := eval_lines_cleared(s.playfield.blocks)
				n_lines_cleared := i32(sa.len(y_positions_cleared))
				set_timer_duration(&s.entry_delay_timer, n_lines_cleared > 0 ? ARE_CLEAR_FRAMES : ARE_FRAMES)
				restart_timer(&s.entry_delay_timer)
				s.lines_just_cleared_y_positions = y_positions_cleared

				// TODO: lines cleared animation
				// toggle show_blocks_cleared bool for all cleared blocks
				// use y_positions_cleared -> store in global
				// TODO: remove lines

				// update score
				if n_lines_cleared > 0 {
					s.score += calc_points(s.level, n_lines_cleared)
				}
				play_sound(.Lock)
				if n_lines_cleared > 0 {
					play_sound(.Clear)
				}
			} else {
				// fall
				s.tetramino.layout_field_position.y += 1
			}
			s.fall_frames = 0
		}
	}


	// locked interlude processing
	if s.tetramino.type == .None  {
		if is_timer_done(s.entry_delay_timer) {
			reset_timer(&s.entry_delay_timer)

			n_lines_cleared := sa.len(s.lines_just_cleared_y_positions)
			s.lines_cleared_accum += i32(n_lines_cleared)
			// update lines_cleared and preview here
			if should_level_increase(s.lines_cleared_accum, s.level) {
				s.level += 1
				s.level_drop_rate = get_current_frames_per_row(LEVEL_DROP_RATES[:], s.level)
				play_sound(.Level)
			}

			// shift playfield down
			for y_to_clear in sa.slice(&s.lines_just_cleared_y_positions) {
				// cleared_y_positions naturally ordered correctly
				// starting from cleared_y_position - 1, copy into row below
				for y := y_to_clear; y >= 1; y -= 1 {
					s.playfield.blocks[y] = s.playfield.blocks[y-1]
				}
			}

			if sa.len(s.lines_just_cleared_y_positions) > 0 {
				sa.clear(&s.lines_just_cleared_y_positions)
				s.show_lines_cleared_flash = true
			}

			// spawn with preview tetra
			spawn_tetramino(s.preview_tetra.type, {}, s)

			// update next preview tetra
			update_preview_tetra(s)

			return
		}
		// animate lines_cleared state
		if int(get_timer_accum(s.entry_delay_timer)) % LINE_CLEAR_ANIMATION_FRAME_INTERVAL == 0 {
			s.show_lines_cleared_flash = !s.show_lines_cleared_flash
		}
		process_timer(&s.entry_delay_timer)
	}

	// move new tetra based on layout_field_pos delta
	new_tetramino_positions := get_tetramino_field_positions(s.tetramino.layout, s.tetramino.layout_field_position)

	sa.clear(&s.block_render_data)
	for row, field_y in s.playfield.blocks {
		for block_type, field_x in row {

			// tetramino data
			if s.tetramino.type != .None {
				is_occupied_by_tetra := false
				for tetra_field_pos in new_tetramino_positions {
					if tetra_field_pos.y == i32(field_y) && tetra_field_pos.x == i32(field_x) {
						sa.append(&s.block_render_data, Block_Render_Data{
							x = PLAYFIELD_BORDER_THICKNESS + f32(field_x) * BLOCK_PIXEL_SIZE,
							y = f32(field_y) * BLOCK_PIXEL_SIZE,
							w = BLOCK_PIXEL_SIZE,
							h = BLOCK_PIXEL_SIZE,
							color = TETRA_COLORS[s.tetramino.type],
							border_color = rl.BLACK,
							highlight_color = rl.RAYWHITE,
						})
						is_occupied_by_tetra = true
					}
				} 
				if is_occupied_by_tetra do continue
			}

			// playfield data and conditional render for animating cleared lines
			if block_type != .None {
				is_block_in_cleared_row := false
				for y in sa.slice(&s.lines_just_cleared_y_positions) {
					if i32(field_y) == y {
						is_block_in_cleared_row = true
						break
					}
				}

				if !is_block_in_cleared_row || (is_block_in_cleared_row && s.show_lines_cleared_flash) {
					sa.append(&s.block_render_data, Block_Render_Data{
						x = PLAYFIELD_BORDER_THICKNESS + f32(field_x) * BLOCK_PIXEL_SIZE,
						y = f32(field_y) * BLOCK_PIXEL_SIZE,
						w = BLOCK_PIXEL_SIZE,
						h = BLOCK_PIXEL_SIZE,
						color = TETRA_COLORS[block_type],
						border_color = rl.BLACK,
						highlight_color = rl.RAYWHITE,
					})
				} else if is_block_in_cleared_row && !s.show_lines_cleared_flash {
					sa.append(&s.block_render_data, Block_Render_Data{
						x = PLAYFIELD_BORDER_THICKNESS + f32(field_x) * BLOCK_PIXEL_SIZE,
						y = f32(field_y) * BLOCK_PIXEL_SIZE,
						w = BLOCK_PIXEL_SIZE,
						h = BLOCK_PIXEL_SIZE,
						color = LINE_CLEAR_FLASH_COLOR,
						border_color = LINE_CLEAR_FLASH_COLOR,
						highlight_color = LINE_CLEAR_FLASH_COLOR,
					})
				}
			}
		}
	}
}

transition_scene :: proc(next: Scene_Type) {
	pr("TRANSITION TO NEXT:", next)
	switch next {
	case .Play:
		play_scene := Play_Scene{}
		init_play_scene(&play_scene)
		g.scene = play_scene
	case .Menu:
		menu_scene := Menu_Scene{}
		init_menu_scene(&menu_scene)
		g.scene = menu_scene
		pr("set scene to Mneu")
	}
}

update_menu_scene :: proc(s: ^Menu_Scene) {
	// pr("update menu")
	process_input_menu_scene(s)
}

Menu_Input :: enum {
	Select_Next_Game_Type,
	Select_Previous_Game_Type,
	Select_Next_Music_Type,
	Select_Previous_Music_Type,
	Toggle_Hard_Mode,
	Goto_Play,
}

MENU_INPUT_MAP := [?]Input_Map_Entry(Menu_Input){
	{.Select_Next_Game_Type, .RIGHT},
	{.Select_Previous_Game_Type, .LEFT},
	{.Select_Next_Music_Type, .DOWN},
	{.Select_Previous_Music_Type, .UP},
	{.Toggle_Hard_Mode, .H},
	{.Goto_Play, .SPACE}, // TODO: if set to ENTER, seems to read the Enter input from Play's Game_Over. Issue even when update_scene put before the update frame's call to transition_scene. Thought about clearing raylib inputs, but cannot do it.
}

process_input_menu_scene :: proc(s: ^Menu_Scene) -> bit_set[Menu_Input] {
	// pr("IN PROC INPUT MENU")
	// Read input
	input: bit_set[Menu_Input]
	for entry in MENU_INPUT_MAP {
		switch entry.input {
		case .Select_Next_Game_Type, .Select_Previous_Game_Type, .Select_Next_Music_Type, .Select_Previous_Music_Type, .Toggle_Hard_Mode, .Goto_Play:
			if rl.IsKeyPressed(entry.key) {
				input += {entry.input}
			}
		}
	}

	// Apply input
	if .Select_Next_Game_Type in input {
		switch s.selected_game_type {
		case .A:
			s.selected_game_type = .B
		case .B:
			s.selected_game_type = .A
		}
		pr("game_type", s.selected_game_type)
	} else if .Select_Previous_Game_Type in input {
		switch s.selected_game_type {
		case .A:
			s.selected_game_type = .B
		case .B:
			s.selected_game_type = .A
		}
		pr("game_type", s.selected_game_type)
	} else if .Select_Next_Music_Type in input {
		switch s.selected_music_type {
		case .A:
			s.selected_music_type = .B
		case .B:
			s.selected_music_type = .C
		case .C:
			s.selected_music_type = .D
		case .D:
			s.selected_music_type = .A
		}
		pr("music_type", s.selected_music_type)
	} else if .Select_Previous_Music_Type in input {
		switch s.selected_music_type {
		case .A:
			s.selected_music_type = .D
		case .B:
			s.selected_music_type = .A
		case .C:
			s.selected_music_type = .B
		case .D:
			s.selected_music_type = .C
		}
		pr("music_type", s.selected_music_type)
	} else if .Toggle_Hard_Mode in input {
		s.is_hard_mode_selected = !s.is_hard_mode_selected
	} else if .Goto_Play in input {
		pr("detected GotoPlay")
		g.next_scene = .Play
	}

	return input
}
