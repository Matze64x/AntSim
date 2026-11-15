#pragma once
#include "modules/common.slang"
#ifdef __SLANG__
import modules.colormaps;
#endif // __SLANG__

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

// how the simulation is shown, which the UI edits
struct Visualizations
{
	Visualization food;
	Visualization food_trail;
	Visualization home_trail;
	Visualization nest;
	Visualization wall;
	float3 ant_wo_food_color;
	// of the ant's leading edge
	float3 ant_wo_food_dir_color;
	float3 ant_w_food_color;
	float3 ant_w_food_dir_color;
};

struct UniformBufferData
{
	float2 range_min;
	float2 range_max;
	Visualizations visualizations;
};

#ifdef __SLANG__

extension Visualization
{
	bool is_shown()
	{
		return color_map != ColorMap::None;
	}

	// of a value in [0, 1]
	float4 get_color(float t)
	{
		switch (color_map)
		{
			case ColorMap::Viridis: return float4(viridis(t), 1.0);
			case ColorMap::Plasma: return float4(plasma(t), 1.0);
			case ColorMap::Magma: return float4(magma(t), 1.0);
			case ColorMap::Inferno: return float4(inferno(t), 1.0);
			// darker for smaller values
			case ColorMap::CustomColor: return float4(color * t, 1.0);
			default: return float4(0.0, 0.0, 0.0, 1.0);
		}
	}
}

#endif // __SLANG__
