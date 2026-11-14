#pragma once
#include "shared/common.slang"

struct Ant
{
	float2 pos;
	// the unit vector the ant walks along; (0, 0) for an ant that hasn't walked yet, which then picks a random one
	float2 dir;
	// Where the ant believes the nest is. Like real ants, it adds up the way it walked (path integration), with an
	// error that grows the farther it walks, until it smells the nest.
	float2 nest_estimate;
	// 0 or 1, since a bool's size differs between Slang's and C++'s buffers
	uint32_t has_food;
};
