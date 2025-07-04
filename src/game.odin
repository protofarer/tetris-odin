package game

import "core:fmt"
import "core:log"
import "core:math/linalg"
import rl "vendor:raylib"

pr :: fmt.println
prf :: fmt.printfln

Void :: struct{}
Vec2 :: [2]f32
Vec2i :: [2]i32
Position :: Vec2

PIXEL_WINDOW_HEIGHT :: 180

WINDOW_W :: 1280
WINDOW_H :: 720
TICK_RATE :: 60

Game_Memory :: struct {
	player: Entity,
	game_state: Game_State,
	resman: ^Resource_Manager,
	debug: bool,
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
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT,
		// target = g.player_pos,
		target = {},
		offset = { w/2, h/2 },
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}
update :: proc() {
	process_input()
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	rl.BeginMode2D(game_camera())
		rect_a := rl.Rectangle{20,20,10,10}
		if aabb_intersects(
			g.player.pos.x, g.player.pos.y, g.player.size.x, g.player.size.y, 
			rect_a.x,rect_a.y,rect_a.width,rect_a.height,
			) {
			draw_sprite(g.player.texture_id, g.player.pos, g.player.size, 0, 1, rl.RED)
			rl.DrawRectangleV({20, 20}, {10, 10}, rl.RED)
		} else {
			draw_sprite(g.player.texture_id, g.player.pos, g.player.size, 0, 1, rl.WHITE)
			rl.DrawRectangleV({20, 20}, {10, 10}, rl.PURPLE)
		}
		rl.DrawRectangleV({-30, -20}, {10, 10}, rl.GREEN)
		if g.debug {
			rl.DrawRectangleLinesEx({g.player.pos.x-1, g.player.pos.y-1, g.player.size.x+2, g.player.size.y+2}, 1, rl.BLUE)
			rl.DrawRectangleLinesEx({rect_a.x-1, rect_a.y-1, rect_a.width+2, rect_a.height+2}, 1, rl.BLUE)
			// 0,0 lines
			rl.DrawLine(-WINDOW_W/2, 0, WINDOW_W/2, 0, rl.BLUE)
			rl.DrawLine(0, -WINDOW_H/2, 0, WINDOW_H/2, rl.BLUE)
		}
		
	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())
		rl.DrawText(fmt.ctprintf("player_pos: %v", g.player.pos), 5, 5, 10, rl.WHITE)
	rl.EndMode2D()

	rl.EndDrawing()
}

process_input :: proc() {
    if rl.IsKeyPressed(.GRAVE) {
        g.debug = !g.debug
    }

	input: rl.Vector2

	if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
		input.y -= 1
	}
	if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
		input.y += 1
	}
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
		input.x -= 1
	}
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
		input.x += 1
	}

	input = linalg.normalize0(input)
	g.player.pos += input * rl.GetFrameTime() * 100

	if rl.IsKeyPressed(.ESCAPE) {
		g.game_state = .Exit
	}

	if rl.IsKeyPressed(.SPACE) {
		play_sound(.Powerup)
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

	g = new(Game_Memory)
	g^ = Game_Memory {
		resman = resman,
	}
}

// clear collections, set initial values
init :: proc() {
	g.game_state = .Play
	g.debug = false

	player: Entity
	init_player(&player)
	g.player = player
}

init_player :: proc(p: ^Entity) {
	p.size = {25, 25}
	p.texture_id = .Player
	p.pos = -p.size / 2
}

draw_sprite :: proc(texture_id: Texture_ID, pos: Position, size: Vec2, rotation: f32 = 0, scale: f32 = 1, tint: rl.Color = rl.WHITE) {
	tex := get_texture(texture_id)
	src_rect := rl.Rectangle {
		0, 0, f32(tex.width), f32(tex.height),
	}
	dst_rect := rl.Rectangle {
		pos.x, pos.y, size.x, size.y,
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
	rl.SetWindowPosition(10, 125)
	rl.SetTargetFPS(500)
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

circle_intersects:: proc(a_pos: Position, a_radius: f32, b_pos: Position, b_radius: f32) -> bool {
	return linalg.length2(a_pos - b_pos) < (a_radius + b_radius) * (a_radius + b_radius)
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
