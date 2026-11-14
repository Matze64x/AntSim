#pragma once
#include "shared/common.slang"

// in meters
AS_CONSTANT float HASH_GRID_CELL_LENGTH = 0.04f;

// in seconds
AS_CONSTANT float PHEROMONE_LIFETIME = 120.0f;

// Ants update cells concurrently without locks: they take food atomically and lay the food trail by writing its expiry
// time, which all ants of a simulation step write the same value to.
struct HashGridCell
{
	// the cell's grid position, packed by get_hash_grid_key()
	uint32_t key;
	int32_t food_amount;
	// The simulated time at which the food trail in the cell expires, PHEROMONE_LIFETIME after an ant carrying food last
	// walked through it; 0 (the start) if none did.
	float food_trail_expiry_time;
};
