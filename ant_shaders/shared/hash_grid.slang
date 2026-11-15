#pragma once
#include "shared/common.slang"
#ifdef __SLANG__
import shared.ant;
#else // __SLANG__
#include "shared/ant.slang"
#endif // __SLANG__

// in meters
AS_CONSTANT float HASH_GRID_CELL_LENGTH = 0.04f;

// The food trail fades exponentially: in this many seconds to half its amount.
AS_CONSTANT float FOOD_TRAIL_HALF_LIFE = 20.0f;
// the faintest food trail that ants smell
AS_CONSTANT float MIN_FOOD_TRAIL = 0.01f;
// The way home that a home trail tells grows by this many meters per second. Slower than ants walk, so that along a
// searching ant's path the older part, nearer to the nest, still tells the shorter way.
AS_CONSTANT float HOME_TRAIL_AGING_SPEED = ANT_SPEED / 2.0f;
// ants ignore home trails that tell a longer way home than this, in meters
AS_CONSTANT float MAX_HOME_DISTANCE = 20.0f;
// Cells store their trails as of a trail epoch, which this many steps make up; after the last one, a pass ages every
// cell's trails to the next epoch. So aging needs no pass per step.
AS_CONSTANT uint32_t TRAIL_EPOCH_STEP_COUNT = 600;

// A cell is free unless it has food or a trail that ants smell. Ants update cells concurrently without locks: they take
// food and lay trails atomically.
struct HashGridCell
{
	// the cell's grid position, packed by get_hash_grid_key()
	uint32_t key;
	int32_t food_amount;
	// The seconds that ants carrying food spent in the cell, weighted by how close to the food they were, each faded since
	// by FOOD_TRAIL_HALF_LIFE, so that busy trails grow stronger; as of the current trail epoch's start
	// (HashGrid::get_food_trail() gives the current amount).
	float food_trail;
	// The shortest way home that ants searching for food knew in the cell, aged since by HOME_TRAIL_AGING_SPEED; as of the
	// current trail epoch's end, and stored as the complement of the distance's bits, so that 0 (the start) means none and
	// an atomic maximum keeps the shortest way (HashGrid::get_home_distance() gives the current distance).
	uint32_t home_trail;
};
