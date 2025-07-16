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
		if s.game_type == .Marathon {
			s.game_type = .Lines
		} else if s.game_type == .Lines {
			s.game_type = .Marathon
		} else {
			unreachable()
		}

	case .Down in input:
		if s.submenu == .Start {
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

		} else if s.submenu == .Marathon {
			s.start_level = max(s.start_level-1, MIN_START_LEVEL)

		} else if s.submenu == .Lines {
			s.garbage_height = max(s.garbage_height-1, MIN_GARBAGE_LEVEL)
		}

	case .Up in input:
		if s.submenu == .Start {
			stop_sound(get_music_id_from_music_type(s.music_type))
			switch s.music_type {
			case .A:
				s.music_type = .C
			case .B:
				s.music_type = .A
			case .C:
				s.music_type = .B
			}
			play_selected_music(s.music_type)

		} else if s.submenu == .Marathon {
			s.start_level = min(s.start_level+1, MAX_START_LEVEL)

		} else if s.submenu == .Lines {
			s.garbage_height = min(s.garbage_height+1, MAX_GARBAGE_LEVEL)
		}

	case .Toggle_Hard_Mode in input:
		s.hard_mode = !s.hard_mode

	case .Goto_Play in input && s.submenu != .Start:
		g.next_scene = .Play

	case .Goto_Submenu in input && s.submenu == .Start:
		if s.game_type == .Marathon {
			s.submenu = .Marathon
		} else if s.game_type == .Lines {
			s.submenu = .Lines
		}

	case .Backto_Start_Submenu in input && s.submenu != .Start:
		s.submenu = .Start
		s.start_level = 0
		s.garbage_height = 0
	}

	return input
}

draw_menu_scene :: proc(s: ^Menu_Scene) {
	{
		tex := get_texture(.Background)
		src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
		dst := rl.Rectangle{0, 0, PIXEL_WINDOW_HEIGHT, PIXEL_WINDOW_HEIGHT}
		rl.DrawTexturePro(tex, src, dst, {}, 0, rl.Color{255,255,255,32})
	}

	switch s.submenu {

	case .Start:
		rect1 := rl.Rectangle{5, 5, 170, 100}
		rl.DrawRectangleRec(rect1, rl.WHITE)

		rl.DrawText("TETRIS", 50, 10, 16, rl.BLACK)
		gt := fmt.ctprintf("Type [left/right]: %v", s.game_type)

		x: i32 = 10
		y: i32 = 35
		rl.DrawText(gt, x, y, 8, rl.BLACK)
		ht := fmt.ctprintf("Hard Mode [h]: %v", s.hard_mode ? "ON" : "OFF")

		y += 15
		rl.DrawText(ht, x, y, 8, rl.BLACK)
		mt := fmt.ctprintf("Music Type [up/down]: %v", s.music_type)

		y += 15
		rl.DrawText(mt, x, y, 8, rl.BLACK)

		y += 20
		x += 25
		rl.DrawText("Enter To Confirm", x, y, 11, rl.BLACK)

		y += 25
		x += 20
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

	case .Marathon:
		rect1 := rl.Rectangle{5, 5, 170, 125}
		rl.DrawRectangleRec(rect1, rl.WHITE)

		rl.DrawText("Marathon Mode", 30, 10, 16, rl.BLACK)

		y: i32 = 55
		x: i32 = 20
		t := fmt.ctprintf("Start Level [up/down]: %v", s.start_level)
		rl.DrawText(t, x, y, 11, rl.BLACK)

		y += 40
		x += 20
		rl.DrawText("Enter To Play", x, y, 11, rl.BLACK)

		y += 15
		x -= 20
		rl.DrawText("Backspace to return", x, y, 11, rl.BLACK)

	case .Lines:
		rect1 := rl.Rectangle{5, 5, 170, 125}
		rl.DrawRectangleRec(rect1, rl.WHITE)

		rl.DrawText("Lines Mode", 50, 10, 16, rl.BLACK)

		y: i32 = 55
		x: i32 = 20
		t := fmt.ctprintf("Lines Height: [up/down]: %v", s.garbage_height)
		rl.DrawText(t, x, y, 11, rl.BLACK)

		y += 40
		x += 30
		rl.DrawText("Enter To Play", x, y, 11, rl.BLACK)

		y += 15
		x -= 20
		rl.DrawText("Backspace to return", x, y, 11, rl.BLACK)
	}

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
}

