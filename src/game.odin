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
RENDER_TEXTURE_SCALE :: 2
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
	app_state: App_State, // CSDR app_state
	resman: ^Resource_Manager,
	scene: Scene,
	next_scene: Maybe(Scene_Type),
	render_texture: rl.RenderTexture2D,
	debug: bool,
	is_music_on: bool,
}

g: ^Game_Memory

App_State :: enum {
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
	Toggle_Music,
}

GLOBAL_INPUT_MAP := [?]Input_Map_Entry(Global_Input){
	{.Toggle_Debug, .GRAVE},
	{.Exit, .ESCAPE},
	{.Toggle_Music, .M},
}

update :: proc() {
	dt := rl.GetFrameTime()

	process_input_global()
	update_scene(&g.scene, dt)

	if next, ok := g.next_scene.?; ok {
		transition_scene(g.scene, next)
		g.next_scene = nil
	}
}

draw :: proc() {
	begin_letterbox_rendering()
	draw_scene(&g.scene)
	// debug
	if g.debug {
		mouse_pos := rl.GetMousePosition()
		text := fmt.ctprintf("mouse_pos: %v,%v", 
			mouse_pos.x, 
			mouse_pos.y,
		)
		rl.DrawText(text, 5, 5, 8, rl.BLUE)

		mouse_pos = get_mouse_position_logical()
		text = fmt.ctprintf("mouse_pos, logical: %v,%v", mouse_pos.x, mouse_pos.y)
		rl.DrawText(text, 5, 15, 8, rl.BLUE)

	}
	end_letterbox_rendering()
}

begin_letterbox_rendering :: proc() {
	rl.BeginTextureMode(g.render_texture)
	rl.ClearBackground(BACKGROUND_COLOR)
	
	// Scale all drawing by RENDER_TEXTURE_SCALE for higher resolution
	camera := rl.Camera2D{zoom = RENDER_TEXTURE_SCALE}
	rl.BeginMode2D(camera)
}

end_letterbox_rendering :: proc() {
	rl.EndMode2D()  // End the scale transform
	rl.EndTextureMode()
	
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	
	// Calculate letterbox dimensions
	viewport_size := get_viewport_size()
	offset_x, offset_y := get_viewport_offset()
	
	// Draw the render texture with letterboxing
	render_texture_size: f32 = PIXEL_WINDOW_HEIGHT * RENDER_TEXTURE_SCALE
	src := rl.Rectangle{0, 0, render_texture_size, -render_texture_size} // negative height flips texture
	dst := rl.Rectangle{-offset_x, -offset_y, viewport_size, viewport_size}
	
	rl.DrawTexturePro(g.render_texture.texture, src, dst, {}, 0, rl.WHITE)
	
	rl.EndDrawing()
}

get_viewport_scale :: proc() -> f32 {
	window_w := f32(rl.GetScreenWidth())
	window_h := f32(rl.GetScreenHeight())
	scale := min(window_w / PIXEL_WINDOW_HEIGHT, window_h / PIXEL_WINDOW_HEIGHT)
	return scale
}

get_viewport_size :: proc() -> f32 {
	scale := get_viewport_scale()
	size := PIXEL_WINDOW_HEIGHT * scale
	return size
}

get_viewport_offset :: proc() -> (f32,f32) {
	window_w := f32(rl.GetScreenWidth())
	window_h := f32(rl.GetScreenHeight())
	size := get_viewport_size()
	off_x := -(window_w - size) / 2
	off_y := -(window_h - size) / 2
	return off_x, off_y
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
	context.logger = log.create_console_logger(.Warning, {
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
		render_texture = rl.LoadRenderTexture(PIXEL_WINDOW_HEIGHT * RENDER_TEXTURE_SCALE, PIXEL_WINDOW_HEIGHT * RENDER_TEXTURE_SCALE),
	}
}

// clear collections, set initial values
init :: proc() {
	g.app_state = .Running
	g.debug = false
	g.is_music_on = true
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
	rl.InitWindow(WINDOW_W, WINDOW_H, "Tetris Engine")
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

	return g.app_state != .Exit
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
		case .Toggle_Debug, .Exit, .Toggle_Music:
			if rl.IsKeyPressed(entry.key) {
				input += {entry.input}
			}
		}
	}
	if .Toggle_Debug in input {
		g.debug = !g.debug
	} else if .Exit in input {
		game_shutdown()
		game_shutdown_window()
	} else if .Toggle_Music in input {
		toggle_music()
	}
}

toggle_music :: proc() {
	g.is_music_on = !g.is_music_on
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

is_music_playing :: proc(music_type: Music_Type) -> bool {
	return is_sound_playing(get_music_id_from_music_type(music_type))
}

BUTTON_DEFAULT_PADDING :: 2

Button :: struct {
	x,y,w,h: i32,
	font_size: i32,
	fill_color: rl.Color,
	fit_contents: bool,
	label: string,
	on_press: proc(s: ^Menu_Scene),
}

buttons: map[string]Button

register_button :: proc(
	label: string, x,y,w,h: i32, 
	font_size: i32 = 8, 
	fill_color: rl.Color = rl.LIGHTGRAY, 
	on_press: proc(s: ^Menu_Scene), 
	fit_contents: bool = false,
	get_display_text: proc() -> string = nil,
	state_ptr: ^bool = nil,
) {

	text := label
	text_cstr := fmt.ctprint(text)
	text_length := rl.MeasureText(text_cstr, font_size)

	w_, h_: i32
	if fit_contents {
		w_ = text_length + BUTTON_DEFAULT_PADDING * 2
		h_ = font_size + BUTTON_DEFAULT_PADDING * 2
	} else {
		w_ = w
		h_ = h
	}
	buttons[label] = Button{
		label= label, x = x,y = y,w = w_,h = h_, 
		font_size = font_size, fill_color = fill_color, fit_contents = fit_contents,
		on_press = on_press,
	}
}

deregister_button :: proc(label: string) {
	delete_key(&buttons, label)
}

clear_buttons :: proc() {
	clear(&buttons)
}

// Label centered, constant padding
draw_button :: proc(label: string, x,y,w,h: i32, font_size: i32 = 8, fill_color: rl.Color = rl.LIGHTGRAY, fit_contents: bool = false, display_text: string = "") {
	x_ := x
	y_ := y
	w_ := w
	h_ := h


	// use display_text otherwise use label
	text := display_text != "" ? display_text : label
	text_cstr := fmt.ctprint(text)
	text_length := rl.MeasureText(text_cstr, font_size)

	if fit_contents {
		w_ = text_length + BUTTON_DEFAULT_PADDING * 2
		h_ = font_size + BUTTON_DEFAULT_PADDING * 2
	}
	text_x := (w_ - text_length) / 2
	text_y := (h_ - font_size) / 2

	rl.DrawRectangle(x_,y_,w_,h_,fill_color)
	rl.DrawRectangleLinesEx(rl.Rectangle{f32(x_), f32(y_), f32(w_), f32(h_)}, 1, rl.BLACK)
	rl.DrawText(text_cstr, x_ + text_x, y_ + text_y, font_size, rl.BLACK)

	if g.debug {
		rl.DrawRectangleLines(x_,y_,w_,h_,rl.BLUE)
	}
}

update_buttons :: proc(s: ^Menu_Scene) {
	is_mouse_pressed := rl.IsMouseButtonPressed(.LEFT) 
	if !is_mouse_pressed do return

	mouse_pos := get_mouse_position_logical()
	for _, b in buttons {
		is_over_button := mouse_pos.x >= f32(b.x) && mouse_pos.x <= f32(b.x + b.w) && mouse_pos.y >= f32(b.y) && mouse_pos.y <= f32(b.y + b.h)
		if is_mouse_pressed && is_over_button {
			if b.on_press != nil {
				b.on_press(s)
			}
			break
		}
	}
}

get_mouse_position_logical :: proc() -> [2]f32 {
	mouse_pos := rl.GetMousePosition() // window coords
	// TODO:
	// logical_mouse_pos := mouse_pos / ()
	// convert to logical coords: viewport offset then scale
	off_x, off_y := get_viewport_offset()
	mouse_pos.x += off_x
	mouse_pos.y += off_y
	mouse_pos /= get_viewport_scale()
	return mouse_pos
}

default_button_proc :: proc(s: ^Menu_Scene) {
	pr("HELLO FROM BUTTON!")
}

// Updated to handle responsive labels
draw_buttons :: proc() {
    for label, b in buttons {
        draw_button(label, b.x, b.y, b.w, b.h, b.font_size, b.fill_color, b.fit_contents, label)
    }
}
