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

// Puts the push constants' food into the cell at its position, taking the slot from whatever cell had it. A single
// thread, since it writes one cell.
[shader("compute")]
[numthreads(1, 1, 1)]
void add_food()
{
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, 0.0);
	const int2 food_hash_grid_pos = get_hash_grid_pos(pc.food_pos);
	HashGridCell* cell = &hash_grid.cells[hash_grid.get_slot(food_hash_grid_pos)];
	if (any(cell.index != food_hash_grid_pos)) cell.pheromone = Pheromone::None;
	cell.index = food_hash_grid_pos;
	cell.food_amount = pc.food_amount;
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
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, ub.total_time);
	const Optional<uint> slot = hash_grid.get_cell(get_hash_grid_pos(pos));
	if (!slot.hasValue) return float4(0.0, 0.0, 0.0, 1.0);
	const HashGridCell cell = hash_grid.cells[slot.value];
	const float pheromone_freshness = hash_grid.get_pheromone_freshness(cell);
	const Pheromone pheromone = hash_grid.get_pheromone(cell);
	if (cell.food_amount > 0 && ub.visualizations.food.is_shown()) return ub.visualizations.food.get_color(float(cell.food_amount) / 255.0);
	if (pheromone == Pheromone::Food && ub.visualizations.food_pheromone.is_shown()) return ub.visualizations.food_pheromone.get_color(pheromone_freshness);
	if (pheromone == Pheromone::Nest && ub.visualizations.nest_pheromone.is_shown()) return ub.visualizations.nest_pheromone.get_color(pheromone_freshness);
	return float4(0.0, 0.0, 0.0, 1.0);
}
