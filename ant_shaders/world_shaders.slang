// The world's shaders: what the user changes, food (add_food) and walls (paint_walls), aging the trails (age_trails),
// and drawing the walls, the nest, food and trails covering the screen (vertex_main, fragment_main).
import modules.hash_grid;
import modules.nest;
import modules.push_constants;
import modules.uniform_buffer;
import modules.walls;
import vkte;

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

// Puts the push constants' food into the cell at its position, taking the slot from whatever cell had it, whose
// trails it clears. A single thread, since it writes one cell.
[shader("compute")]
[numthreads(1, 1, 1)]
void add_food()
{
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, pc.step);
	const int2 food_hash_grid_pos = get_hash_grid_pos(pc.food_pos);
	const uint key = get_hash_grid_key(food_hash_grid_pos);
	HashGridCell* cell = &hash_grid.cells[hash_grid.get_slot(food_hash_grid_pos)];
	if (cell.key != key)
	{
		cell.key = key;
		cell.food_trail = 0.0;
		cell.home_trail = 0;
	}
	cell.food_amount = pc.food_amount;
}

float get_distance_to_line(float2 pos, float2 from, float2 to)
{
	const float2 line = to - from;
	const float t = dot(line, line) > 0.0 ? saturate(dot(pos - from, line) / dot(line, line)) : 0.0;
	return distance(pos, from + t * line);
}

// Paints or erases the walls of the cells that the push constants' wall stroke covers. A thread per cell of the stroke's
// bounding box, starting at its minimum.
[shader("compute")]
[numthreads(8, 8, 1)]
void paint_walls(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
	const WallStroke stroke = pc.wall_stroke;
	const int2 index = get_hash_grid_pos(min(stroke.from, stroke.to) - stroke.radius) + int2(dispatch_thread_id.xy);
	const Walls walls = Walls(vkte::get_buffer<uint32_t>(pc.walls).get_pointer());
	if (!is_in_world(index) || get_distance_to_line(get_hash_grid_cell_pos(index), stroke.from, stroke.to) > stroke.radius) return;
	walls.set_wall(index, stroke.brush == WallBrush::Paint);
}

// Ages every cell's trails to the next trail epoch, after the last step of one. A thread per slot.
[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void age_trails(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
	const uint slot = dispatch_thread_id.x;
	if (slot >= pc.hash_grid_capacity) return;
	HashGridCell* cells = vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer();
	const float epoch_length = float(TRAIL_EPOCH_STEP_COUNT) * SIMULATION_TIME_STEP;
	cells[slot].food_trail *= get_food_trail_fade(epoch_length);
	const uint home_trail = cells[slot].home_trail;
	if (home_trail != 0) cells[slot].home_trail = encode_home_distance(decode_home_distance(home_trail) + HOME_TRAIL_AGING_SPEED * epoch_length);
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
	const Walls walls = Walls(vkte::get_buffer<uint32_t>(pc.walls).get_pointer());
	if (walls.is_wall(get_hash_grid_pos(pos)) && ub.visualizations.wall.is_shown()) return ub.visualizations.wall.get_color(1.0);
	if (distance(pos, nest.pos) < nest.get_radius() && ub.visualizations.nest.is_shown())
	{
		return ub.visualizations.nest.get_color(nest.get_level_progress());
	}
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, pc.step);
	const Optional<uint> slot = hash_grid.get_cell(get_hash_grid_pos(pos));
	if (!slot.hasValue) return float4(0.0, 0.0, 0.0, 1.0);
	const HashGridCell cell = hash_grid.cells[slot.value];
	if (cell.food_amount > 0 && ub.visualizations.food.is_shown()) return ub.visualizations.food.get_color(float(cell.food_amount) / 255.0);
	// on a logarithmic scale from the faintest trail (0) to one 100 times as strong (1)
	const float food_trail_strength = saturate(log2(hash_grid.get_food_trail(cell) / MIN_FOOD_TRAIL) / log2(100.0));
	if (hash_grid.has_food_trail(cell) && ub.visualizations.food_trail.is_shown()) return ub.visualizations.food_trail.get_color(food_trail_strength);
	// from no way home (0) to the nest (1)
	const float home_trail_strength = 1.0 - hash_grid.get_home_distance(cell) / MAX_HOME_DISTANCE;
	if (hash_grid.has_home_trail(cell) && ub.visualizations.home_trail.is_shown()) return ub.visualizations.home_trail.get_color(home_trail_strength);
	return float4(0.0, 0.0, 0.0, 1.0);
}
