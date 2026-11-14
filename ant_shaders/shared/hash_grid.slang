#pragma once
#include "shared/common.slang"

// in meters
AS_CONSTANT float HASH_GRID_CELL_LENGTH = 0.04f;

// The food trail fades exponentially: in this many seconds to half its amount.
AS_CONSTANT float FOOD_TRAIL_HALF_LIFE = 20.0f;
// the faintest food trail that ants smell; a cell with a fainter one and no food is free
AS_CONSTANT float MIN_FOOD_TRAIL = 0.01f;
// Cells store their food trail as of the start of a trail epoch, which this many steps make up; after the last one, a
// pass fades every cell's trail to the next epoch's start. So fading needs no pass per step.
AS_CONSTANT uint32_t FOOD_TRAIL_EPOCH_STEP_COUNT = 600;

// Ants update cells concurrently without locks: they take food and lay the food trail atomically.
struct HashGridCell
{
	// the cell's grid position, packed by get_hash_grid_key()
	uint32_t key;
	int32_t food_amount;
	// The seconds that ants carrying food spent in the cell, each faded since by FOOD_TRAIL_HALF_LIFE, so that busy
	// trails grow stronger; as of the current trail epoch's start (HashGrid::get_food_trail() gives the current amount).
	float food_trail;
};
