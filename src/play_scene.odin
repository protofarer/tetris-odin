package game

import "core:log"
import "core:math/rand"
import "core:fmt"
import sa "core:container/small_array"
import rl "vendor:raylib"

// 3 holes per row
GARBAGE_PATTERN := [MAX_GARBAGE_LEVEL * 2][10]u8 {
    { 1,1,1,0,1,1,0,1,1,0 }, // Height 0
    { 0,1,1,1,0,1,1,1,0,1 }, // Height 1
    { 1,0,1,1,1,0,1,1,1,0 }, // Height 2
    { 1,1,0,1,1,1,0,1,0,1 }, // Height 3
    { 0,1,1,0,1,1,1,0,1,1 }, // Height 4
    { 1,0,1,1,0,1,1,1,1,0 }, // Height 5
    { 1,1,0,1,1,0,1,1,0,1 }, // Height 6
    { 0,1,1,1,1,0,1,0,1,1 }, // Height 7
    { 1,1,1,0,1,0,1,1,0,1 }, // Height 8
    { 0,1,0,1,1,1,0,1,1,1 }, // Height 9
}

Play_Scene :: struct {
	block_render_data: sa.Small_Array(PLAYFIELD_BLOCK_W * PLAYFIELD_BLOCK_H, Block_Render_Data),
	blocks: Playfield_Blocks,
	lines_just_cleared_y_positions: sa.Small_Array(PLAYFIELD_BLOCK_H, i32),

	tetramino: Tetramino,
	preview_tetra: Tetramino,

	input_repeat_delay_timer: Timer, // DAS
	input_repeat_timer: Timer, // ARR
	entry_delay_timer: Timer, // ARE

	level: i32,
	score: i32,
	fall_frames: i32,
	soft_drop_counter: i32,
	lines_cleared_accum: i32,
	level_drop_rate: i32,
	start_level: i32, // Marathon Game Type
	garbage_height: i32, // Lines Game Type
	hard_mode: bool,
	is_game_over: bool,
	is_game_won: bool,
	is_paused: bool,
	show_lines_cleared_flash: bool,

	previous_tetra_type: Tetramino_Type,
	music_type: Music_Type,

	input: bit_set[Play_Input],
}

Playfield_Blocks :: [PLAYFIELD_BLOCK_H][PLAYFIELD_BLOCK_W]Tetramino_Type

Block_Render_Data :: struct {
	x,y: f32,
	w,h: f32,
	color: rl.Color,
	border_color: rl.Color,
	highlight_color: rl.Color,
}

init_play_scene :: proc(s: ^Play_Scene, game_type: Game_Type, game_settings: Game_Settings) {
	sa.clear(&s.block_render_data)
	// clear playfield
	for y in 0..<PLAYFIELD_BLOCK_H {
		for x in 0..<PLAYFIELD_BLOCK_W {
			s.blocks[y][x] = .None
		}
	}
	sa.clear(&s.lines_just_cleared_y_positions)

	s.input_repeat_delay_timer = create_timer(DAS_FRAMES, .One_Shot, .Tick, 1, "input_repeat_delay_timer")
	s.input_repeat_timer = create_timer(ARR_FRAMES, .One_Shot, .Tick, 1, "input_repeat_timer")
	s.entry_delay_timer = create_timer(ARE_FRAMES, .One_Shot, .Tick, 1, "entry_delay")

	s.level = game_settings.start_level
	s.score = 0
	s.fall_frames = 0
	s.soft_drop_counter = 0
	s.lines_cleared_accum = 0
	s.level_drop_rate = get_drop_rate(LEVEL_DROP_RATES[:], s.level, game_settings.hard_mode)
	s.start_level = game_settings.start_level
	s.garbage_height = game_settings.garbage_height
	s.hard_mode = game_settings.hard_mode
	s.is_game_over = false
	s.is_game_won = false
	s.is_paused = false
	s.show_lines_cleared_flash = true
	s.music_type = game_settings.music_type

	// Fill garbage height for lines game type: 2 * garbage_height
	for y in 0..<2*s.garbage_height {
		row := GARBAGE_PATTERN[y]
		for x in 0..<PLAYFIELD_BLOCK_W {
			if row[x] == 1 {
				tt := roll_seven()
				set_playfield_block(s, i32(x), i32(PLAYFIELD_BLOCK_H - 1 - y), tt)
			}
		}
	}

	spawn_preview_tetra(s)
	starting_tetra_type := roll_start_game(s^)
	spawn_tetramino(starting_tetra_type, {}, s)

	log.info("Play scene initialization done.")
}

update_play_scene :: proc(s: ^Play_Scene) {
	input := process_input_play_scene(s)

	if !s.is_game_over && !s.is_game_won && !s.is_paused {
		update_playfield(s, input)
	}
	update_music(s.music_type, s.is_game_over, s.is_game_won, s.is_paused)
	update_block_render_data(s)
}

Play_Input :: enum {
	Drop,
	Drop_Release,
	Shift_Left,
	Shift_Right,
	Rotate_CCW,
	Rotate_CW,
	Toggle_Music,
	Toggle_Preview,
	Exit,
	Toggle_Debug,
	Goto_Menu,
	Debug_Increase_Level,
	Debug_Decrease_Level,
	Debug_Toggle_Hard_Mode,
	Pause,
}

PLAY_INPUT_MAP := [?]Input_Map_Entry(Play_Input){
	{.Toggle_Debug, .GRAVE},
	{.Drop, .DOWN},
	{.Shift_Left, .LEFT},
	{.Shift_Right, .RIGHT},
	{.Rotate_CCW, .Z},
	{.Rotate_CW, .X},
	{.Drop, .S}, // soft drop
	{.Drop_Release, .S},
	{.Shift_Left, .A},
	{.Shift_Right, .D},
	{.Toggle_Music, .M},
	{.Toggle_Preview, .P},
	{.Exit, .ESCAPE},
	{.Goto_Menu, .ENTER},
	{.Debug_Increase_Level, .EQUAL},
	{.Debug_Decrease_Level, .MINUS},
	{.Debug_Toggle_Hard_Mode, .ZERO},
	{.Pause, .P},
}

process_input_play_scene :: proc(s: ^Play_Scene) -> bit_set[Play_Input] {
	input: bit_set[Play_Input]

	// Read input
	for entry in PLAY_INPUT_MAP {
		switch entry.input {
		case .Toggle_Debug, .Toggle_Music, .Toggle_Preview, .Exit, .Goto_Menu, .Debug_Increase_Level, .Debug_Decrease_Level, .Debug_Toggle_Hard_Mode, .Pause:
			if rl.IsKeyPressed(entry.key) {
				input += {entry.input}
			}

		case .Shift_Left, .Shift_Right, .Rotate_CCW, .Rotate_CW:
			delay_and_repeat_input(s, &input, entry.key, entry.input)
			if rl.IsKeyDown(entry.key) {
			}

		// (soft) Drop
		case .Drop:
			if rl.IsKeyDown(entry.key) {
				input += {entry.input}
			}
		case .Drop_Release:
			if rl.IsKeyReleased(entry.key) {
				input += {entry.input}
			}
		}
	}

	switch {
	case .Pause in input:
		if !s.is_game_over && !s.is_game_won {
			s.is_paused = !s.is_paused
		}
	}
	if .Drop_Release in input {
		s.soft_drop_counter = 0
	}

	if g.debug {
		if rl.IsKeyPressed(.G) {
			s.is_game_over = true
		}
		if rl.IsKeyPressed(.T) {
			s.is_game_won = true
		}
	}

	if (s.is_game_over || s.is_game_won) && .Goto_Menu in input {
		transition_scene(s^, .Menu)
	}

	if .Debug_Increase_Level in input {
		if s.level + 1 < 20 {
			s.level += 1
			s.level_drop_rate = get_drop_rate(LEVEL_DROP_RATES[:], s.level, s.hard_mode)
			play_sound(.Stage_Clear)
		}
	} else if .Debug_Decrease_Level in input {
		if s.level - 1 > 0 {
			s.level -= 1
			s.level_drop_rate = get_drop_rate(LEVEL_DROP_RATES[:], s.level, s.hard_mode)
			play_sound(.Stage_Clear)
		}
	} else if .Debug_Toggle_Hard_Mode in input {
		s.hard_mode = !s.hard_mode
	}
	return input
}

update_playfield :: proc(s: ^Play_Scene, input: bit_set[Play_Input]) {
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
				if tetra_type, in_bounds := get_playfield_block(intended_x, i32(pos.y), s.blocks); !in_bounds || tetra_type != .None {
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
				if tetra_type, in_bounds := get_playfield_block(intended_position.x, intended_position.y, s.blocks); !in_bounds || tetra_type != .None {
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
		drop_rate := .Drop in input ? SOFT_DROP_RATE : s.level_drop_rate
		if s.fall_frames < drop_rate {
			s.fall_frames += 1
		} else {
			if .Drop in input {
				s.soft_drop_counter += 1
			} 

			// check next down position for collision: block or ground
			is_locked := false
			for pos in old_tetra_positions {
				tetra_type, in_bounds := get_playfield_block(pos.x, pos.y + 1, s.blocks)
				if !in_bounds || tetra_type != .None {
					is_locked = true
					break
				} 
			}

			if is_locked {
				// locked: operations associated with tetra locking/setting into a position

				// create blocks at tetra locked positions
				tetra_positions := get_tetramino_field_positions(s.tetramino.layout, s.tetramino.layout_field_position)
				for pos in tetra_positions {
					set_playfield_block(s, pos.x, pos.y, s.tetramino.type)
				}

				s.previous_tetra_type = s.tetramino.type

				// NOTE: this zeroes out the layout, thus no blocks to operate on (or render!)
				// NOTE: other code keys off this value to signify no player controllable tetra on screen aka non-existent player tetra aka post-lock operations
				s.tetramino = { type = .None }

				y_positions_cleared := eval_lines_cleared(s.blocks)
				s.lines_just_cleared_y_positions = y_positions_cleared

				n_lines_cleared := i32(sa.len(y_positions_cleared))
				set_timer_duration(&s.entry_delay_timer, n_lines_cleared > 0 ? ARE_CLEAR_FRAMES : ARE_FRAMES)

				restart_timer(&s.entry_delay_timer)

				// soft drop points
				if .Drop in input {
					s.score += s.soft_drop_counter
					s.soft_drop_counter = 0
				}

				// lines cleared points
				if n_lines_cleared > 0 {
					s.score += calc_points(s.level, n_lines_cleared)
					if test_line_mode_win(s.lines_cleared_accum) {
						s.is_game_won = true
					}
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

	// Interlude processing, between locked and next tetra spawn
	if s.tetramino.type == .None  {
		if is_timer_done(s.entry_delay_timer) {
			reset_timer(&s.entry_delay_timer)

			n_lines_cleared := sa.len(s.lines_just_cleared_y_positions)
			s.lines_cleared_accum += i32(n_lines_cleared)

			// update lines_cleared and preview here
			if should_level_increase(s.lines_cleared_accum, s.level, s.start_level) {
				s.level += 1
				s.level_drop_rate = get_drop_rate(LEVEL_DROP_RATES[:], s.level, s.hard_mode)
				play_sound(.Stage_Clear)
			}

			// shift playfield down
			for y_to_clear in sa.slice(&s.lines_just_cleared_y_positions) {
				// cleared_y_positions naturally ordered correctly
				// starting from cleared_y_position - 1, copy into row below
				for y := y_to_clear; y >= 1; y -= 1 {
					s.blocks[y] = s.blocks[y-1]
				}
			}

			if sa.len(s.lines_just_cleared_y_positions) > 0 {
				sa.clear(&s.lines_just_cleared_y_positions)
				s.show_lines_cleared_flash = true
			}

			// spawn with preview tetra
			spawn_tetramino(s.preview_tetra.type, {}, s)

			// test game over: if spawned tetra intersects with existing playfield block
			for pos in get_tetramino_field_positions(s.tetramino.layout, s.tetramino.layout_field_position) {
				if tetra_type, in_bounds := get_playfield_block(pos.x, pos.y, s.blocks); in_bounds && tetra_type != .None {
					s.is_game_over = true
					break
				}
			}

			// update next preview tetra
			spawn_preview_tetra(s)

			return
		}
		// animate lines_cleared state
		if int(get_timer_accum(s.entry_delay_timer)) % LINE_CLEAR_ANIMATION_FRAME_INTERVAL == 0 {
			s.show_lines_cleared_flash = !s.show_lines_cleared_flash
		}
		process_timer(&s.entry_delay_timer)
	}
}

draw_play_scene :: proc(s: ^Play_Scene) {
	// Background Texture
	{
		PLAYFIELD_BG_COLOR :: rl.Color{147,210,255,160}
		tex := get_texture(.Background)
		src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
		dst := rl.Rectangle{0, 0, PIXEL_WINDOW_HEIGHT, PIXEL_WINDOW_HEIGHT}
		rl.DrawTexturePro(tex, src, dst, {}, 0, PLAYFIELD_BG_COLOR)
	}


	// Playfield Borders
	{
		tex := get_texture(.Border)
		src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
		{ // left
			rl.DrawRectangle(0,0, PLAYFIELD_BORDER_THICKNESS, PIXEL_WINDOW_HEIGHT, rl.GRAY)
			dst := rl.Rectangle{0, 0, PLAYFIELD_BORDER_THICKNESS, PIXEL_WINDOW_HEIGHT}
			rl.DrawTexturePro(tex, src, dst, {}, 0, rl.RAYWHITE)
		}
		{ // right
			rl.DrawRectangle(
				PLAYFIELD_BORDER_THICKNESS + PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE, 0,
				PLAYFIELD_BORDER_THICKNESS, PIXEL_WINDOW_HEIGHT, 
				rl.GRAY,
			)
			dst := rl.Rectangle{
				PLAYFIELD_BORDER_THICKNESS + PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE, 
				0, 
				PLAYFIELD_BORDER_THICKNESS, 
				PIXEL_WINDOW_HEIGHT,
			}
			rl.DrawTexturePro(tex, src, dst, {}, 0, rl.RAYWHITE)
		}
	}

	// Playfield + Tetra
	for brd in sa.slice(&s.block_render_data) {
		draw_block(brd.x, brd.y, brd.w, brd.h, brd.color, brd.border_color, brd.highlight_color)
	}

	// Panel
	PANEL_BLEND_COLOR :: rl.Color{30,30,30,128}
	rl.DrawRectangleV({PANEL_X, PANEL_Y}, {PANEL_WIDTH, PANEL_HEIGHT}, PANEL_BLEND_COLOR)

	PANEL_TEXT_BG_COLOR :: rl.Color{255,255,255,225}
	TEXT_X :: PANEL_X + 8

	SCORE_LABEL_POS :: Vec2i{TEXT_X, 5}
	SCORE_VALUE_POS :: Vec2i{SCORE_LABEL_POS.x, SCORE_LABEL_POS.y + 15}

	rect_score := rl.Rectangle{f32(SCORE_LABEL_POS.x-3), f32(SCORE_LABEL_POS.y-3), 45, 30}
	rl.DrawRectangleRounded(rect_score, 0.1, 3, PANEL_TEXT_BG_COLOR)
	rl.DrawText("SCORE", SCORE_LABEL_POS.x, SCORE_LABEL_POS.y, 9, rl.BLACK)
	rl.DrawText(fmt.ctprint(s.score), SCORE_VALUE_POS.x, SCORE_VALUE_POS.y, 10, rl.BLACK)

	LEVEL_LABEL_POS :: Vec2i{TEXT_X, 50}
	LEVEL_VALUE_POS :: Vec2i{LEVEL_LABEL_POS.x, LEVEL_LABEL_POS.y + 10}
	rect_level := rl.Rectangle{f32(LEVEL_LABEL_POS.x-3), f32(LEVEL_LABEL_POS.y-3), 45, 23}
	rl.DrawRectangleRounded(rect_level, 0.1, 3,  PANEL_TEXT_BG_COLOR)
	rl.DrawText("LEVEL", LEVEL_LABEL_POS.x, LEVEL_LABEL_POS.y, 10, rl.BLACK)
	rl.DrawText(fmt.ctprint(s.level), LEVEL_VALUE_POS.x, LEVEL_VALUE_POS.y, 10, rl.BLACK)
	if s.hard_mode {
		rl.DrawText("H", LEVEL_VALUE_POS.x+30, LEVEL_VALUE_POS.y, 10, rl.BLACK)
	}

	LINES_LABEL_POS :: Vec2i{TEXT_X, 75}
	LINES_VALUE_POS :: Vec2i{LINES_LABEL_POS.x, LINES_LABEL_POS.y + 10}
	rect_lines := rl.Rectangle{f32(LINES_LABEL_POS.x-3), f32(LINES_LABEL_POS.y-3), 45, 23}
	rl.DrawRectangleRounded(rect_lines, 0.1, 3,  PANEL_TEXT_BG_COLOR)
	rl.DrawText("LINES", LINES_LABEL_POS.x, LINES_LABEL_POS.y, 10, rl.BLACK)
	rl.DrawText(fmt.ctprint(s.lines_cleared_accum), LINES_VALUE_POS.x, LINES_VALUE_POS.y, 10, rl.BLACK)

	PREVIEW_BOX_POS :: Vec2{TEXT_X, 110}
	PREVIEW_BOX_SIZE :: Vec2{50,50}
	rect_preview := rl.Rectangle{f32(PREVIEW_BOX_POS.x-3), f32(PREVIEW_BOX_POS.y-3), PREVIEW_BOX_SIZE.x, PREVIEW_BOX_SIZE.y}
	rl.DrawRectangleRounded(rect_preview, 0.1, 3, PANEL_TEXT_BG_COLOR)

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

	PLAYFIELD_TEXT_BG_COLOR :: rl.Color{255,255,255,192}

	if s.is_game_over {
		y1: i32 = 40
		x1: i32 = 40
		rect := rl.Rectangle{f32(x1-15), f32(y1)-9, 65, 40}
		rl.DrawRectangleRounded(rect, 0.1, 3, PLAYFIELD_TEXT_BG_COLOR)

		rl.DrawText("GAME", x1, y1, 12, rl.BLACK)
		y1 += 12
		rl.DrawText("OVER", x1, y1, 12, rl.BLACK)

		y2: i32 = 95
		x2: i32 = 25
		rect2 := rl.Rectangle{f32(x2-10), f32(y2)-10, 90, 70}
		rl.DrawRectangleRounded(rect2, 0.1, 3, PLAYFIELD_TEXT_BG_COLOR)

		rl.DrawText("PLEASE ", x2, y2, 12, rl.BLACK)
		y2 += 10
		rl.DrawText("TRY", x2, y2, 12, rl.BLACK)
		y2 += 10
		rl.DrawText("AGAIN", x2, y2, 12, rl.BLACK)
		y2 += 15
		rl.DrawText("HIT ENTER", x2, y2, 12, rl.BLACK)
		rl.DrawRectangle(x2-5, y2+12, 80, 1, rl.BLACK)

	} else if s.is_game_won {

		y1: i32 = 30
		x1: i32 = 35
		rect1 := rl.Rectangle{f32(x1-12), f32(y1)-5, 75, 40}
		rl.DrawRectangleRounded(rect1, 0.1, 3, PLAYFIELD_TEXT_BG_COLOR)

		rl.DrawText("YOU", x1, y1, 16, rl.BLACK)
		y1 += 12
		rl.DrawText("WIN ! ! !", x1, y1, 16, rl.BLACK)


		y2: i32 = 75
		x2: i32 = 23
		rect2 := rl.Rectangle{f32(x2)-5, f32(y2)-5, 85, 45}
		rl.DrawRectangleRounded(rect2, 0.1, 3, PLAYFIELD_TEXT_BG_COLOR)
		rl.DrawText("CLEARED", x2, y2, 12, rl.BLACK)
		y2 += 12
		rl.DrawText("REQUIRED", x2, y2, 12, rl.BLACK)
		y2 += 12
		rl.DrawText("25 LINES", x2, y2, 12, rl.BLACK)
		y2 += 30

		x3: i32 = 15
		rect3 := rl.Rectangle{f32(x3)-5, f32(y2)-5, 100, 32}
		rl.DrawRectangleRounded(rect3, 0.1, 3, PLAYFIELD_TEXT_BG_COLOR)
		rl.DrawText("HIT ENTER TO" , x3, y2, 12, rl.BLACK)
		y2 += 12
		rl.DrawText("PLAY AGAIN" , x3, y2, 12, rl.BLACK)

	} else if s.is_paused {
		y1: i32 = 70
		x1: i32 = 30
		rect := rl.Rectangle{f32(x1-10), f32(y1)-5, 80, 20}
		rl.DrawRectangleRounded(rect, 0.1, 3, PLAYFIELD_TEXT_BG_COLOR)

		x1 -= 5
		rl.DrawText("PAUSED (P)", x1, y1, 12, rl.BLACK)
	}

	// Debug
	if g.debug {
		for x in 0..<PLAYFIELD_BLOCK_W+1 {
			for y in 0..<PLAYFIELD_BLOCK_H+1 {
				rl.DrawLine(
					i32(x * BLOCK_PIXEL_SIZE + PLAYFIELD_BORDER_THICKNESS), 
					0, 
					i32(x*BLOCK_PIXEL_SIZE +  PLAYFIELD_BORDER_THICKNESS),
					PLAYFIELD_BLOCK_H * BLOCK_PIXEL_SIZE,
					rl.BLUE,
				)
				rl.DrawLine(
					PLAYFIELD_BORDER_THICKNESS,
					i32(y * BLOCK_PIXEL_SIZE),
					PLAYFIELD_BLOCK_W * BLOCK_PIXEL_SIZE + PLAYFIELD_BORDER_THICKNESS,
					i32(y*BLOCK_PIXEL_SIZE),
					rl.BLUE,
				)
			}
		}
	}

	if g.debug {
		rl.DrawText(
			fmt.ctprintf(
				"layout_pos: %v\nlevel_drop_rate: %v", 
				s.tetramino.layout_field_position, 
				s.level_drop_rate,
			),
			5, 5, 10, rl.WHITE,
		)
	}

}

update_block_render_data :: proc(s: ^Play_Scene) {
	new_tetramino_positions := get_tetramino_field_positions(s.tetramino.layout, s.tetramino.layout_field_position)

	sa.clear(&s.block_render_data)
	for row, field_y in s.blocks {
		for block_type, field_x in row {

			// When tetra in play
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
						break
					}
				} 
				if is_occupied_by_tetra do continue
			}

			// Playfield and the conditional render for animating cleared lines
			if block_type != .None {
				is_block_in_cleared_row := false
				for y in sa.slice(&s.lines_just_cleared_y_positions) {
					if i32(field_y) == y {
						is_block_in_cleared_row = true
						break
					}
				}

				// Render block
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

				// When row is flashed, render flash color
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

update_music :: proc(music_type: Music_Type, game_over: bool, game_won: bool, paused: bool) {
	// play game win sound
	if game_won && is_sound_playing(get_music_id_from_music_type(music_type)){
		stop_sound(get_music_id_from_music_type(music_type))
		play_sound(.Stage_Clear)
	}

	// play game over sound
	if game_over && is_sound_playing(get_music_id_from_music_type(music_type)) {
		stop_sound(get_music_id_from_music_type(music_type))
		play_sound(.Game_Over)
	}

	// loop music
	if !is_sound_playing(get_music_id_from_music_type(music_type)) && (!game_won && !game_over && !paused) {
		play_selected_music(music_type)
	}

	if paused && is_sound_playing(get_music_id_from_music_type(music_type)) {
		stop_sound(get_music_id_from_music_type(music_type))
	}
}

set_playfield_block :: proc(s: ^Play_Scene, x: i32, y: i32, tetra_type: Tetramino_Type) {
	if y < 0 || y >= PLAYFIELD_BLOCK_H || x < 0 || x >= PLAYFIELD_BLOCK_W {
		log.warnf("Failed to set block, coord out of range. x: %v, y: %v", x, y)
		return
	}
	s.blocks[y][x] = tetra_type
}

get_drop_rate :: proc(table: []i32, level: i32, hard_mode: bool) -> i32 {
	idx := min(level + (hard_mode ? 10 : 0), MAX_LEVEL - 1)
	return table[idx]
}

calc_points :: proc(level: i32, n_lines_cleared: i32) -> i32 {
	if n_lines_cleared <= 3 {
		idx := int(n_lines_cleared) - 1
		return POINTS_TABLE[idx] * (level + 1)
	} else {
		return POINTS_TABLE[3] * (level + 1)
	} 
}

should_level_increase :: proc(lines_cleared_accum: i32, level: i32, start_level: i32) -> bool {
	lines_next_level := (start_level * LINES_PER_LEVEL + LINES_PER_LEVEL) + 
		LINES_PER_LEVEL * (level - start_level)
	if lines_cleared_accum >= lines_next_level && level < 20 {
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
	.I, .J, .L, .T,
}

ALL_TETRA_CHOICE := [?]Tetramino_Type{
	.I, .J, .L, .T, .S, .Z, .O,
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

spawn_preview_tetra :: proc(s: ^Play_Scene) {
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
						layout_field_position.y + i32(layout_local_y),
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

test_line_mode_win :: proc(lines_cleared_accum: i32) -> bool {
	if lines_cleared_accum >= 25 {
		return true
	}
	return false
}
