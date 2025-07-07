package game
import sa "core:container/small_array"

N_LAYOUTS_PER_TETRAMINO_TYPE :: 4

Tetramino :: struct {
	type: Tetramino_Type,
	layout: Tetramino_Layout,
	layout_i: int,
	layout_field_position: Position,
	intended_relative_position: Position,
}

Tetramino_Type :: enum {
	None,
	I,
	J,
	L,
	Z,
	S,
	T,
	O,
}

// Layouts correspond to clockwise progression in increasing index
// All tetraminos have 4 layouts, some layouts are repeats
// Layout within playfield is the tetramino's "placement" position whereas blocks filled are the "collision" positions
// TODO: bit_field

Tetramino_Layout :: [4][4]u8
Tetramino_Layout_Table :: sa.Small_Array(4, Tetramino_Layout)
LAYOUT_TABLES: [Tetramino_Type]Tetramino_Layout_Table

init_layout_tables :: proc() {
	sa.append(&LAYOUT_TABLES[.T], Tetramino_Layout{
		{0,0,0,0},
		{1,1,1,0},
		{0,1,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.T], Tetramino_Layout{
		{0,1,0,0},
		{1,1,0,0},
		{0,1,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.T], Tetramino_Layout{
		{0,1,0,0},
		{1,1,1,0},
		{0,0,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.T], Tetramino_Layout{
		{0,1,0,0},
		{0,1,1,0},
		{0,1,0,0},
		{0,0,0,0},
	})
}

tetramino_next_layout :: proc() {
	g.tetramino.layout_i = (g.tetramino.layout_i + 1) % N_LAYOUTS_PER_TETRAMINO_TYPE
	g.tetramino.layout = get_layout(g.tetramino.type, g.tetramino.layout_i)
}

tetramino_previous_layout :: proc() {
	g.tetramino.layout_i = (g.tetramino.layout_i - 1) % N_LAYOUTS_PER_TETRAMINO_TYPE
	g.tetramino.layout = get_layout(g.tetramino.type, g.tetramino.layout_i)
}

get_layout :: proc(t: Tetramino_Type, i: int) -> Tetramino_Layout  {
	return sa.get(LAYOUT_TABLES[t], i)
}
