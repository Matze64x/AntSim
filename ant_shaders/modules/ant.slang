#pragma once
#include "modules/common.slang"

// in meters per second
AS_CONSTANT float ANT_SPEED = 0.2f;

enum class AntState : uint32_t
{
	// for food; starts from the nest
	Search,
	// food home
	CarryFood,
	// home without food, after searching for longer than trails reach
	GiveUp
};

struct Ant
{
	float2 pos;
	// the unit vector the ant walks along; (0, 0) for an ant that hasn't walked yet, which then picks a random one
	float2 dir;
	// Where the ant believes the nest is. Like real ants, it adds up the way it walked (path integration), with an
	// error that grows the farther it walks, until it smells the nest.
	float2 nest_estimate;
	// The meters the ant walked since it left the nest or the food: its way back there, which it shortens to that of a
	// trail it crosses that tells a shorter one, and which it lays in its trail.
	float distance_walked;
	AntState state;
	// The meters an explorer still explores on its way, 0 for an ant that follows the trails (see
	// BehaviorSettings::explorer_share).
	float exploration_left;
};
