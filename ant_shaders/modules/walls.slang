#pragma once
#include "modules/common.slang"

// The world reaches this many cells (of HASH_GRID_CELL_LENGTH, so 100 m) from the origin along each axis; beyond it is
// wall.
AS_CONSTANT int32_t WORLD_HALF_CELL_COUNT = 2500;
AS_CONSTANT uint32_t WORLD_CELL_COUNT = uint32_t(2 * WORLD_HALF_CELL_COUNT);
// the uints of the walls buffer, which has a bit per cell of the world
AS_CONSTANT uint32_t WALL_WORD_COUNT = WORLD_CELL_COUNT * WORLD_CELL_COUNT / 32;

enum class WallBrush : uint32_t
{
	None,
	Paint,
	Erase
};

// what the wall brush covered during a frame: the cells within the radius of the line from `from` to `to`
struct WallStroke
{
	float2 from;
	float2 to;
	float radius;
	WallBrush brush;
};

AS_FUNCTION bool is_in_world(int2 index)
{
	return index.x >= -WORLD_HALF_CELL_COUNT && index.y >= -WORLD_HALF_CELL_COUNT && index.x < WORLD_HALF_CELL_COUNT && index.y < WORLD_HALF_CELL_COUNT;
}

// of a cell in the world, in the walls buffer
AS_FUNCTION uint32_t get_wall_bit(int2 index)
{
	return uint32_t(index.y + WORLD_HALF_CELL_COUNT) * WORLD_CELL_COUNT + uint32_t(index.x + WORLD_HALF_CELL_COUNT);
}

#ifdef __SLANG__

// The world's walls, a bit per cell, through a pointer. Cells outside the world are walls.
struct Walls
{
	uint32_t* words;

	bool is_wall(int2 index)
	{
		if (!is_in_world(index)) return true;
		const uint bit = get_wall_bit(index);
		return (words[bit / 32u] & (1u << (bit % 32u))) != 0u;
	}

	// of a cell in the world; atomically, since other threads set the other bits of the word
	void set_wall(int2 index, bool is_wall)
	{
		const uint bit = get_wall_bit(index);
		Atomic<uint32_t>* word = (Atomic<uint32_t>*)&words[bit / 32u];
		const uint mask = 1u << (bit % 32u);
		if (is_wall) word.or(mask);
		else word.and(~mask);
	}
}

#endif // __SLANG__
