#pragma once
#include "shared/common.slang"

enum class ColorMap : uint32_t
{
	None,
	Viridis,
	Plasma,
	Magma,
	Inferno,
	// Visualization::color
	CustomColor
};

// how a quantity of the simulation is shown
struct Visualization
{
	float3 color;
	ColorMap color_map;
};

struct UniformBufferData
{
	float2 range_min;
	float2 range_max;
	Visualization food;
	Visualization food_pheromone;
	Visualization nest;
	Visualization nest_pheromone;
	float3 ant_wo_food_color;
	float3 ant_wo_food_dir_color;
	float3 ant_w_food_color;
	float3 ant_w_food_dir_color;
	uint32_t frame_idx;
	float frame_time;
	float total_time;
};
