#pragma once
#include "shared/common.slang"

// in meters
AS_CONSTANT float HASH_GRID_CELL_LENGTH = 0.04f;

// in seconds
AS_CONSTANT float PHEROMONE_LIFETIME = 120.0f;

// which way the pheromone in a cell leads: ants without food leave the nest's, ants that carry food the food's
enum class Pheromone : uint32_t
{
	None,
	Nest,
	Food
};

struct HashGridCell
{
	int2 index;
	int32_t food_amount;
	float pheromone_lifetime;
	float pheromone_distance;
	Pheromone pheromone;
	// 0 or 1 (a bool's size differs between Slang's and C++'s buffers): whether the cell holds the index's data
	uint32_t active;
	// 0 or 1, set atomically while an ant updates the cell
	uint32_t locked;
};
