import include.colormaps;
import shared.uniform_buffer;

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
			case ColorMap::CustomColor: return float4(color, 1.0);
			default: return float4(0.0, 0.0, 0.0, 1.0);
		}
	}
}
