package game

import "core:fmt"
import "core:log"
import rl "vendor:raylib"

pr :: fmt.println

Void :: struct{}
Vec2 :: [2]f32
Vec2i :: [2]i32
Position :: Vec2i

WINDOW_W :: 720
WINDOW_H :: 720
PIXEL_WINDOW_HEIGHT :: 180
TICK_RATE :: 60

BLOCK_PIXEL_SIZE :: PIXEL_WINDOW_HEIGHT / PLAYFIELD_BLOCK_H
BACKGROUND_COLOR :: rl.Color{192,192,192,255}
PLAYFIELD_BLOCK_H :: 18
PLAYFIELD_BLOCK_W :: 10
PLAYFIELD_BORDER_THICKNESS :: 10

PANEL_X :: PLAYFIELD_BORDER_THICKNESS * 2 + (PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE)
PANEL_Y :: 0
PANEL_WIDTH :: WINDOW_W - PANEL_X
PANEL_HEIGHT :: WINDOW_H

DAS_FRAMES :: 23
ARR_FRAMES :: 9
ARE_CLEAR_FRAMES :: 93
ARE_FRAMES :: 2

LINE_CLEAR_ANIMATION_FRAME_INTERVAL :: 10
LINE_CLEAR_FLASH_COLOR :: rl.GRAY

// Frames per row move
LEVEL_DROP_RATES := [?]i32{
	53, 49, 45, 41, 37, 33, 28, 22, 17, 11, 10, 9, 8, 7, 6, 6, 5, 5, 4, 4, 3, 
}
SOFT_DROP_RATE :: 3

POINTS_TABLE := [?]i32{
	40,		// single
	100,	// double
	300,	// triple
	1200,	// tetris
}

LINES_PER_LEVEL :: 10
MAX_LEVEL :: len(LEVEL_DROP_RATES)

Game_Memory :: struct {
	game_state: Game_State, // CSDR app_state
	resman: ^Resource_Manager,
	debug: bool,
	scene: Scene,
	next_scene: Maybe(Scene_Type),
	render_texture: rl.RenderTexture2D,
}

g: ^Game_Memory

Game_State :: enum {
	Running,
	Exit,
}

Input_Map_Entry :: struct ($T: typeid) {
	input: T,
	key: rl.KeyboardKey,
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

	process_input_global()
	update_scene(&g.scene, &g.next_scene, dt)

	if next, ok := g.next_scene.?; ok {
		transition_scene(g.scene, next)
		g.next_scene = nil
	}
}

draw :: proc() {
	begin_letterbox_rendering()
	draw_scene(&g.scene)
	end_letterbox_rendering()
}

begin_letterbox_rendering :: proc() {
	rl.BeginTextureMode(g.render_texture)
	rl.ClearBackground(BACKGROUND_COLOR)
}

end_letterbox_rendering :: proc() {
	rl.EndTextureMode()
	
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	
	// Calculate letterbox dimensions
	window_w := f32(rl.GetScreenWidth())
	window_h := f32(rl.GetScreenHeight())
	
	scale := min(window_w / PIXEL_WINDOW_HEIGHT, window_h / PIXEL_WINDOW_HEIGHT)
	viewport_size := PIXEL_WINDOW_HEIGHT * scale
	
	offset_x := (window_w - viewport_size) / 2
	offset_y := (window_h - viewport_size) / 2
	
	// Draw the render texture with letterboxing
	src := rl.Rectangle{0, 0, PIXEL_WINDOW_HEIGHT, -PIXEL_WINDOW_HEIGHT} // negative height flips texture
	dst := rl.Rectangle{offset_x, offset_y, viewport_size, viewport_size}
	
	rl.DrawTexturePro(g.render_texture.texture, src, dst, {}, 0, rl.WHITE)
	
	rl.EndDrawing()
}

screen_to_logical_coords :: proc(screen_pos: rl.Vector2) -> rl.Vector2 {
	window_w := f32(rl.GetScreenWidth())
	window_h := f32(rl.GetScreenHeight())
	
	scale := min(window_w / PIXEL_WINDOW_HEIGHT, window_h / PIXEL_WINDOW_HEIGHT)
	viewport_size := PIXEL_WINDOW_HEIGHT * scale
	
	offset_x := (window_w - viewport_size) / 2
	offset_y := (window_h - viewport_size) / 2
	
	logical_x := (screen_pos.x - offset_x) / scale
	logical_y := (screen_pos.y - offset_y) / scale
	
	return {logical_x, logical_y}
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
		render_texture = rl.LoadRenderTexture(PIXEL_WINDOW_HEIGHT, PIXEL_WINDOW_HEIGHT),
	}
}

// clear collections, set initial values
init :: proc() {
	g.game_state = .Running
	g.debug = false
	transition_scene({}, .Menu)
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
	rl.InitWindow(WINDOW_W, WINDOW_H, "Tetris Remake")
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
	rl.UnloadRenderTexture(g.render_texture)
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

process_input_global :: proc() {
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
}

play_sound :: proc(id: Sound_ID) {
    rl.PlaySound(get_sound(id))
}

is_sound_playing :: proc(id: Sound_ID) -> bool {
    return rl.IsSoundPlaying(get_sound(id))
}

stop_sound :: proc(id: Sound_ID) {
	rl.StopSound(get_sound(id))
}

restart_sound :: proc(id: Sound_ID) {
	if is_sound_playing(id) {
		stop_sound(id)
	}
	play_sound(id)
}
