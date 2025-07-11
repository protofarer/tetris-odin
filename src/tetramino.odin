package game
import sa "core:container/small_array"
import rl "vendor:raylib"

N_LAYOUTS_PER_TETRAMINO_TYPE :: 4
TETRAMINO_BLOCKS_PER_LAYOUT :: 4


Tetramino :: struct {
	type: Tetramino_Type,
	layout: Tetramino_Layout,
	layout_idx: int,
	layout_field_position: Position,
	color: rl.Color,
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

TETRA_COLORS := [Tetramino_Type]rl.Color{
	.None = rl.BLANK,
	.I = rl.YELLOW,
	.J = rl.RED,
	.L = rl.PINK,
	.Z = rl.ORANGE,
	.S = rl.PURPLE,
	.T = rl.BLUE,
	.O = rl.GREEN,
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
	sa.append(&LAYOUT_TABLES[.I], Tetramino_Layout{
		{0,0,0,0},
		{1,1,1,1},
		{0,0,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.I], Tetramino_Layout{
		{0,1,0,0},
		{0,1,0,0},
		{0,1,0,0},
		{0,1,0,0},
	})
	sa.append(&LAYOUT_TABLES[.I], Tetramino_Layout{
		{0,0,0,0},
		{1,1,1,1},
		{0,0,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.I], Tetramino_Layout{
		{0,1,0,0},
		{0,1,0,0},
		{0,1,0,0},
		{0,1,0,0},
	})
	sa.append(&LAYOUT_TABLES[.O], Tetramino_Layout{
		{0,0,0,0},
		{0,1,1,0},
		{0,1,1,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.O], Tetramino_Layout{
		{0,0,0,0},
		{0,1,1,0},
		{0,1,1,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.O], Tetramino_Layout{
		{0,0,0,0},
		{0,1,1,0},
		{0,1,1,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.O], Tetramino_Layout{
		{0,0,0,0},
		{0,1,1,0},
		{0,1,1,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.J], Tetramino_Layout{
		{0,0,0,0},
		{1,1,1,0},
		{0,0,1,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.J], Tetramino_Layout{
		{0,1,0,0},
		{0,1,0,0},
		{1,1,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.J], Tetramino_Layout{
		{1,0,0,0},
		{1,1,1,0},
		{0,0,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.J], Tetramino_Layout{
		{0,1,1,0},
		{0,1,0,0},
		{0,1,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.L], Tetramino_Layout{
		{0,0,0,0},
		{1,1,1,0},
		{1,0,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.L], Tetramino_Layout{
		{1,1,0,0},
		{0,1,0,0},
		{0,1,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.L], Tetramino_Layout{
		{0,0,1,0},
		{1,1,1,0},
		{0,0,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.L], Tetramino_Layout{
		{0,1,0,0},
		{0,1,0,0},
		{0,1,1,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.S], Tetramino_Layout{
		{0,0,0,0},
		{0,1,1,0},
		{1,1,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.S], Tetramino_Layout{
		{1,0,0,0},
		{1,1,0,0},
		{0,1,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.S], Tetramino_Layout{
		{0,0,0,0},
		{0,1,1,0},
		{1,1,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.S], Tetramino_Layout{
		{1,0,0,0},
		{1,1,0,0},
		{0,1,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.Z], Tetramino_Layout{
		{0,0,0,0},
		{1,1,0,0},
		{0,1,1,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.Z], Tetramino_Layout{
		{0,1,0,0},
		{1,1,0,0},
		{1,0,0,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.Z], Tetramino_Layout{
		{0,0,0,0},
		{1,1,0,0},
		{0,1,1,0},
		{0,0,0,0},
	})
	sa.append(&LAYOUT_TABLES[.Z], Tetramino_Layout{
		{0,1,0,0},
		{1,1,0,0},
		{1,0,0,0},
		{0,0,0,0},
	})
}

get_next_layout :: proc(t: Tetramino) -> (Tetramino_Layout, int) {
	layout_idx := (t.layout_idx + 1) % N_LAYOUTS_PER_TETRAMINO_TYPE
	layout := get_layout(t.type, layout_idx)
	return layout, layout_idx
}

get_previous_layout :: proc(t: Tetramino) -> (Tetramino_Layout, int) {
	layout_idx := (t.layout_idx - 1 + N_LAYOUTS_PER_TETRAMINO_TYPE) % N_LAYOUTS_PER_TETRAMINO_TYPE
	layout := get_layout(t.type, layout_idx)
	return layout, layout_idx
}

get_layout :: proc(t: Tetramino_Type, i: int) -> Tetramino_Layout  {
	return sa.get(LAYOUT_TABLES[t], i)
}

