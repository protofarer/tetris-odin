// CSDR Reusing and generalizing the code in this file for use in a simple game template. Currently OK for tetris.

package game

import "core:log"


Scene_Type :: enum {
	Menu,
	Play,
}

Scene :: union {
	Menu_Scene,
	Play_Scene,
}

update_scene :: proc(scene: ^Scene,  dt: f32) {
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

transition_scene :: proc(curr_scene: Scene, next_scene_type: Scene_Type) {
	switch next_scene_type {
	case .Play:
		clear_buttons()
		play_scene := Play_Scene{}
		s := curr_scene.(Menu_Scene)
		game_type := s.game_type
		game_settings := s.game_settings
		init_play_scene(&play_scene, game_type, game_settings)
		g.scene = play_scene
		log.debug("Transition to play scene")
	case .Menu:
		clear_buttons()
		menu_scene := Menu_Scene{}
		init_menu_scene(&menu_scene)
		g.scene = menu_scene
		log.debug("Transition to menu scene")
	}
}

play_selected_music :: proc(music_type: Music_Type) {
	id := get_music_id_from_music_type(music_type)
	restart_sound(id)
}

stop_selected_music :: proc(music_type: Music_Type) {
	id := get_music_id_from_music_type(music_type)
	stop_sound(id)
}

get_music_id_from_music_type :: proc(music_type: Music_Type) -> Sound_ID {
	switch music_type {
	case .A:
		return .Music_A
	case .B:
		return .Music_B
	case .C:
		return .Music_C
	case:
		return .Music_A
	}
}
