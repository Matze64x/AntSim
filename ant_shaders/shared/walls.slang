#pragma once
#include "shared/common.slang"

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
