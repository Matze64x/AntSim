import shared.walls;

// The world's walls, a bit per cell, through a pointer. Cells outside the world are walls.
struct Walls
{
	uint32_t* words;

	bool is_in_world(int2 index)
	{
		return all(index >= -WORLD_HALF_CELL_COUNT) && all(index < WORLD_HALF_CELL_COUNT);
	}

	bool is_wall(int2 index)
	{
		if (!is_in_world(index)) return true;
		const uint bit = get_bit(index);
		return (words[bit / 32u] & (1u << (bit % 32u))) != 0u;
	}

	// of a cell in the world; atomically, since other threads set the other bits of the word
	void set_wall(int2 index, bool is_wall)
	{
		const uint bit = get_bit(index);
		Atomic<uint32_t>* word = (Atomic<uint32_t>*)&words[bit / 32u];
		const uint mask = 1u << (bit % 32u);
		if (is_wall) word.or(mask);
		else word.and(~mask);
	}

	static uint get_bit(int2 index)
	{
		const uint2 world_index = uint2(index + WORLD_HALF_CELL_COUNT);
		return world_index.y * WORLD_CELL_COUNT + world_index.x;
	}
}
