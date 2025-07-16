package game

import "core:fmt"
import rl "vendor:raylib"

Menu_Scene :: struct {
	using game_settings: Game_Settings,
	submenu: Submenu,
	game_type: Game_Type,
}

Game_Settings :: struct {
	start_level: i32,
	garbage_height: i32,
	hard_mode: bool,
	music_type: Music_Type,
}

Music_Type :: enum u8 { A, B, C }

Submenu :: enum {
	Start,
	Marathon,
	Lines,
}

Game_Type :: enum {
	Marathon,
	Lines,
}

init_menu_scene :: proc(s: ^Menu_Scene) {
	s.game_settings = {
		start_level = 0,
		garbage_height = 0,
		hard_mode = false,
		music_type = .A,
	}
	s.submenu = .Start
	s.game_type = .Marathon
	play_selected_music(s.music_type)

	clear_submenu_buttons()
	register_start_menu_buttons()
}

update_menu_scene :: proc(s: ^Menu_Scene) {
	process_input_menu_scene(s)

	if g.is_music_on {
		// loop
		if !is_music_playing(s.music_type){
			play_selected_music(s.music_type)
		}
	} else {
		stop_selected_music(s.music_type)
	}

	// detect button presses
	update_buttons(s)
}

Menu_Input :: enum {
	Toggle_Game_Type,
	Up,
	Down,
	Toggle_Hard_Mode,
	Goto_Play,
	Goto_Submenu,
	Backto_Start_Submenu,
}

MENU_INPUT_MAP := [?]Input_Map_Entry(Menu_Input){
	{.Toggle_Game_Type, .RIGHT},
	{.Toggle_Game_Type, .LEFT},
	{.Up, .UP},
	{.Down, .DOWN},
	{.Toggle_Hard_Mode, .H},
	{.Goto_Submenu, .ENTER},
	{.Backto_Start_Submenu, .BACKSPACE},
	{.Goto_Play, .ENTER},
}

MIN_START_LEVEL :: 0
MAX_START_LEVEL :: 9
MIN_GARBAGE_LEVEL :: 0
MAX_GARBAGE_LEVEL :: 5

process_input_menu_scene :: proc(s: ^Menu_Scene) -> bit_set[Menu_Input] {
	input: bit_set[Menu_Input]
	for entry in MENU_INPUT_MAP {
		switch entry.input {
		case .Toggle_Game_Type, .Up, .Down, .Toggle_Hard_Mode, .Goto_Play, .Goto_Submenu, .Backto_Start_Submenu:
			if rl.IsKeyPressed(entry.key) {
				input += {entry.input}
			}
		}
	}

	// Apply input
	switch {

	case .Toggle_Game_Type in input:
		toggle_game_type(s)

	case .Down in input:
		if s.submenu == .Start {
			cycle_music(s)

		} else if s.submenu == .Marathon {
			increase_start_level(s)

		} else if s.submenu == .Lines {
			increase_garbage_height(s)
		}

	case .Up in input:
		if s.submenu == .Marathon {
			increase_start_level(s)

		} else if s.submenu == .Lines {
			increase_garbage_height(s)
		}

	case .Toggle_Hard_Mode in input:
		toggle_hard_mode(s)

	case .Goto_Play in input && s.submenu != .Start:
		goto_play(nil)

	case .Goto_Submenu in input && s.submenu == .Start:
		goto_submenu(s)

	case .Backto_Start_Submenu in input && s.submenu != .Start:
		goto_start_menu(s)
	}

	return input
}

draw_menu_scene :: proc(s: ^Menu_Scene) {
	{
		tex := get_texture(.Background)
		src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
		dst := rl.Rectangle{0, 0, PIXEL_WINDOW_HEIGHT, PIXEL_WINDOW_HEIGHT}
		rl.DrawTexturePro(tex, src, dst, {}, 0, PLAYFIELD_BG_COLOR)
	}

	switch s.submenu {

	case .Start:
		rect1 := rl.Rectangle{5, 5, 170, 170}
		rl.DrawRectangleRec(rect1, rl.WHITE)

		rl.DrawText("TETRIS", 50, 10, 16, rl.BLACK)

		x: i32 = 10
		y: i32 = 35
		gt := fmt.ctprintf("                 %v", s.game_type)
		rl.DrawText(gt, x, y, 8, rl.BLACK)

		y += 17
		ht := fmt.ctprintf("                 %v", s.hard_mode ? "ON" : "OFF")
		rl.DrawText(ht, x, y, 8, rl.BLACK)
		mt := fmt.ctprintf("                 %v", s.music_type)

		y += 17
		rl.DrawText(mt, x, y, 8, rl.BLACK)

		// y += 20
		// x += 25
		// rl.DrawText("Enter To Confirm", x, y, 11, rl.BLACK)

		// y += 25
		y += 20
		// x += 20
		x += 45
		rl.DrawText("CONTROLS", x, y, 11, rl.BLACK)

		x -= 30
		y += 15
		rl.DrawText("Shift: Left/Right or A/D", x, y, 8, rl.BLACK)

		y += 12
		rl.DrawText("Rotate: Z/X", x, y, 8, rl.BLACK)

		y += 12
		rl.DrawText("Drop: Down or S", x, y, 8, rl.BLACK)

		y += 12
		rl.DrawText("Pause: P", x, y, 8, rl.BLACK)
		x += 55
		rl.DrawText("Toggle Music: M", x, y, 8, rl.BLACK)

	case .Marathon:
		rect1 := rl.Rectangle{5, 5, 170, 170}
		rl.DrawRectangleRec(rect1, rl.WHITE)

		rl.DrawText("Marathon Mode", 30, 10, 16, rl.BLACK)

		y: i32 = 55
		x: i32 = 20
		t := fmt.ctprintf("Start Level      %v", s.start_level)
		rl.DrawText(t, x, y, 11, rl.BLACK)

		y += 40
		x += 20
		// rl.DrawText("Enter To Play", x, y, 11, rl.BLACK)

		y += 15
		x -= 20
		// rl.DrawText("Backspace to return", x, y, 11, rl.BLACK)

	case .Lines:
		rect1 := rl.Rectangle{5, 5, 170, 170}
		rl.DrawRectangleRec(rect1, rl.WHITE)

		rl.DrawText("Lines Mode", 50, 10, 16, rl.BLACK)

		y: i32 = 55
		x: i32 = 20
		t := fmt.ctprintf("Lines Height:     %v", s.garbage_height)
		rl.DrawText(t, x, y, 11, rl.BLACK)

		y += 40
		x += 30
		// rl.DrawText("Enter To Play", x, y, 11, rl.BLACK)

		y += 15
		x -= 20
		// rl.DrawText("Backspace to return", x, y, 11, rl.BLACK)
	}

	for _, b in buttons {
		draw_button(b.label, b.x,b.y,b.w,b.h,b.font_size,b.fill_color,b.fit_contents)
	}
}

toggle_game_type :: proc(s: ^Menu_Scene) {
	switch s.game_type {
	case .Marathon:
		s.game_type = .Lines
	case .Lines:
		s.game_type = .Marathon
	}
}

toggle_hard_mode :: proc(s: ^Menu_Scene) {
	s.hard_mode = !s.hard_mode
}

cycle_music :: proc(s: ^Menu_Scene) {
	stop_sound(get_music_id_from_music_type(s.music_type))
	switch s.music_type {
	case .A:
		s.music_type = .B
	case .B:
		s.music_type = .C
	case .C:
		s.music_type = .A
	}
	play_selected_music(s.music_type)
}

goto_submenu :: proc(s: ^Menu_Scene) {
	clear_start_menu_buttons()
	if s.game_type == .Marathon {
		s.submenu = .Marathon
		register_marathon_submenu_buttons()
	} else if s.game_type == .Lines {
		s.submenu = .Lines
		register_lines_submenu_buttons()
	}
}

increase_start_level :: proc(s: ^Menu_Scene) {
	s.start_level = min(s.start_level+1, MAX_START_LEVEL)
}

decrease_start_level :: proc(s: ^Menu_Scene) {
	s.start_level = max(s.start_level-1, MIN_START_LEVEL)
}

increase_garbage_height :: proc(s: ^Menu_Scene) {
	s.garbage_height = min(s.garbage_height+1, MAX_GARBAGE_LEVEL)
}

decrease_garbage_height :: proc(s: ^Menu_Scene) {
	s.garbage_height = max(s.garbage_height-1, MIN_GARBAGE_LEVEL)
}

goto_start_menu :: proc(s: ^Menu_Scene) {
	s.submenu = .Start
	s.start_level = 0
	s.garbage_height = 0
	clear_submenu_buttons()
	register_start_menu_buttons()
}

clear_submenu_buttons :: proc() {
	delete_key(&buttons, "+")
	delete_key(&buttons, "-")
	delete_key(&buttons, "Enter To Play")
	delete_key(&buttons, "Back")
}

clear_start_menu_buttons :: proc() {
	delete_key(&buttons, "Game Type")
	delete_key(&buttons, "Hard Mode")
	delete_key(&buttons, "Music Type")
	delete_key(&buttons, "Enter To Confirm")

}

register_start_menu_buttons :: proc() {
	register_button("Game Type", 10, 33, 20, 8, 8, rl.LIGHTGRAY, toggle_game_type, true)
	register_button("Hard Mode", 10, 50, 20, 8, 8, rl.LIGHTGRAY, toggle_hard_mode, true)
	register_button("Music Type", 10, 67, 20, 8, 8, rl.LIGHTGRAY, cycle_music, true)
	register_button("Enter To Confirm", 45, 157, 20, 8, 8, rl.LIGHTGRAY, goto_submenu, true)
}

register_lines_submenu_buttons :: proc() {
	register_button("+", 124, 55, 20, 8, 8, rl.LIGHTGRAY,  increase_garbage_height, true)
	register_button("-", 94, 55, 20, 8, 8, rl.LIGHTGRAY, decrease_garbage_height, true)
	register_button("Enter To Play", 46, 157, 20, 8, 8, rl.LIGHTGRAY, goto_play, true)
	register_button("Back", 10, 157, 20, 8, 8, rl.LIGHTGRAY, goto_start_menu, true)
}

register_marathon_submenu_buttons :: proc() {
	register_button("+", 124, 55, 20, 8, 8, rl.LIGHTGRAY,  increase_start_level, true)
	register_button("-", 94, 55, 20, 8, 8, rl.LIGHTGRAY, decrease_start_level, true)
	register_button("Enter To Play", 46, 157, 20, 8, 8, rl.LIGHTGRAY, goto_play, true)
	register_button("Back", 10, 157, 20, 8, 8, rl.LIGHTGRAY, goto_start_menu, true)
}

goto_play :: proc(s: ^Menu_Scene) {
	g.next_scene = .Play
}
