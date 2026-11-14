#pragma once
#include "shared/common.slang"

// in meters
AS_CONSTANT float HASH_GRID_CELL_LENGTH = 0.04f;

// in seconds
AS_CONSTANT float PHEROMONE_LIFETIME = 120.0f;

// which way a pheromone leads: ants without food leave the nest's, ants that carry food the food's
enum class Pheromone : uint32_t
{
	Nest,
	Food
};

// one kind of pheromone in a cell
struct Trail
{
	// the simulated time at which the pheromone expires, PHEROMONE_LIFETIME after it was laid; 0 (the start) if none was
	float expiry_time;
	// how far the ant that laid it had come from the nest or the food
	float distance;
};

// A cell can have both pheromones. Ants update cells concurrently without locks: they take food atomically and lay a
// trail by writing its two members, which all ants of a simulation step write the same expiry time to.
struct HashGridCell
{
	// the cell's grid position, packed by get_hash_grid_key()
	uint32_t key;
	int32_t food_amount;
	Trail nest_trail;
	Trail food_trail;
};
