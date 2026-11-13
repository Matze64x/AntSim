import include.hash_grid;
import include.nest;
import include.visualization;
import shared.hash_grid;
import shared.nest;
import shared.push_constants;
import shared.uniform_buffer;
import vkte;

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

HashGrid get_hash_grid()
{
	return HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity);
}

// adds the food of the push constants, ages the pheromones and frees the cells without food whose pheromones expired
[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void step_cells(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
	const uint slot = dispatch_thread_id.x;
	const HashGrid hash_grid = get_hash_grid();
	if (!hash_grid.is_valid(slot)) return;
	const UniformBufferData ub = vkte::get_single_element_buffer<UniformBufferData>(pc.uniform_buffer);
	HashGridCell* cell = &hash_grid.cells[slot];
	if (pc.food_amount > 0)
	{
		const int2 food_hash_grid_pos = get_hash_grid_pos(pc.food_pos);
		if (slot == hash_grid.get_slot(food_hash_grid_pos))
		{
			cell.food_amount = pc.food_amount;
			cell.active = 1;
			cell.index = food_hash_grid_pos;
		}
	}
	if (cell.food_amount == 0 && cell.pheromone_lifetime > PHEROMONE_LIFETIME)
	{
		cell.active = 0;
		cell.pheromone = Pheromone::None;
		cell.locked = 0;
	}
	else
	{
		cell.locked = 0;
		cell.pheromone_lifetime += ub.frame_time;
	}
}

struct ScreenVertex
{
	float4 position : SV_Position;
	// (0, 0) at the screen's top left
	float2 screen_uv : TEXCOORD0;
};

// a triangle covering the screen
[shader("vertex")]
ScreenVertex vertex_main(uint vertex_id : SV_VertexID)
{
	ScreenVertex output;
	output.screen_uv = float2((vertex_id << 1) & 2, vertex_id & 2);
	output.position = float4(output.screen_uv * 2.0 - 1.0, 0.0, 1.0);
	return output;
}

[shader("fragment")]
float4 fragment_main(ScreenVertex input) : SV_Target
{
	const UniformBufferData ub = vkte::get_single_element_buffer<UniformBufferData>(pc.uniform_buffer);
	const Nest nest = vkte::get_single_element_buffer<Nest>(pc.nest);
	const float2 pos = input.screen_uv * (ub.range_max - ub.range_min) + ub.range_min;
	if (distance(pos, nest.pos) < nest.get_radius() && ub.visualizations.nest.is_shown())
	{
		return ub.visualizations.nest.get_color(nest.get_level_progress());
	}
	const HashGrid hash_grid = get_hash_grid();
	const Optional<uint> slot = hash_grid.get_cell(get_hash_grid_pos(pos));
	if (!slot.hasValue) return float4(0.0, 0.0, 0.0, 1.0);
	const HashGridCell cell = hash_grid.cells[slot.value];
	const float pheromone_freshness = (PHEROMONE_LIFETIME - cell.pheromone_lifetime) / PHEROMONE_LIFETIME;
	if (cell.food_amount > 0 && ub.visualizations.food.is_shown()) return ub.visualizations.food.get_color(float(cell.food_amount) / 255.0);
	if (cell.pheromone == Pheromone::Food && ub.visualizations.food_pheromone.is_shown()) return ub.visualizations.food_pheromone.get_color(pheromone_freshness);
	if (cell.pheromone == Pheromone::Nest && ub.visualizations.nest_pheromone.is_shown()) return ub.visualizations.nest_pheromone.get_color(pheromone_freshness);
	return float4(0.0, 0.0, 0.0, 1.0);
}
