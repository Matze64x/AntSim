#pragma once
#include "shared/common.slang"
#ifdef __SLANG__
import vkte;
#else // __SLANG__
#include "vkte/resource_handles.hpp"
#endif // __SLANG__

// of every compute shader, which runs one thread per ant or hash grid slot
AS_CONSTANT uint32_t WORKGROUP_SIZE = 32;

// the push constants of every pipeline: the bindless buffers, which the shaders resolve with vkte::get_buffer(), and the
// sizes of the ant and hash grid buffers
struct PushConstants
{
	vkte::BufferHandle ants;
	vkte::BufferHandle nest;
	vkte::BufferHandle hash_grid;
	vkte::BufferHandle uniform_buffer;
	uint32_t ant_count;
	uint32_t hash_grid_capacity;
	// where food is added this frame, if food_amount > 0
	float2 food_pos;
	int32_t food_amount;
	// keeps the size a multiple of 8 bytes, as Slang lays out the block
	uint32_t pad0;
};
