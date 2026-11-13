#pragma once
#include "shared/common.slang"

// how much an ant wants to reach its target; a target is only replaced by one of a higher priority
enum class TargetPriority : uint32_t
{
	// the ant needs a new target
	None,
	// a random target near the ant
	Wander,
	// a cell with the pheromone that leads where the ant wants to go
	Pheromone,
	// food if the ant carries none, else the nest
	FoodOrNest
};

struct Ant
{
	float2 pos;
	float2 dir;
	float2 target;
	float distance_to_poi;
	// track how many other pheromones the ant sees to increase probability of emitting one
	float pheromone_emit_scale;
	TargetPriority target_priority;
	// 0 or 1, since a bool's size differs between Slang's and C++'s buffers
	uint32_t has_food;
};
