import include.ant;
import include.hash_grid;
import include.nest;
import include.random;
import shared.ant;
import shared.hash_grid;
import shared.nest;
import shared.push_constants;
import shared.uniform_buffer;
import vkte;

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

static const float ANT_SPEED = 0.2;
static const float ANT_SEARCH_RADIUS = 0.2;
// the cells an ant looks at per frame for a better target
static const int TARGET_SEARCH_SAMPLE_COUNT = 32;
// how far ants may go from the origin along each axis
static const float WORLD_BOUND = 100.0;

// Samples cells around the ant for a better target than the one it has: food if it carries none, else the nest, or the
// closest pheromone that leads there.
void look_for_target(inout Ant ant, HashGrid hash_grid, Nest nest, AntTime ant_time, inout Random rng)
{
	const int2 ant_hash_grid_pos = get_hash_grid_pos(ant.pos);
	Optional<uint> target_slot = none;
	TargetPriority target_priority = ant.target_priority;
	float target_distance = float.maxValue;
	// cells at random positions within the search radius (a cell may be sampled more than once)
	for (int i = 0; i < TARGET_SEARCH_SAMPLE_COUNT; i++)
	{
		const int2 offset = int2(round(rng.next_float2_in_disk() * (ANT_SEARCH_RADIUS / HASH_GRID_CELL_LENGTH)));
		// skip the cell in which the ant currently is
		if (all(offset == 0)) continue;
		const Optional<uint> slot = hash_grid.get_cell(ant_hash_grid_pos + offset);
		if (!slot.hasValue) continue;
		const HashGridCell cell = hash_grid.cells[slot.value];
		TargetPriority priority = TargetPriority::None;
		float distance_to_goal = float.maxValue;
		if (ant.has_food == 0)
		{
			if (cell.food_amount > 0 && ant_time.chance(rng, 0.1, 0.95))
			{
				priority = TargetPriority::FoodOrNest;
				distance_to_goal = 0.0;
			}
			else if (hash_grid.get_pheromone(cell) == Pheromone::Food)
			{
				priority = TargetPriority::Pheromone;
				distance_to_goal = cell.pheromone_distance;
			}
		}
		else
		{
			const float nest_distance = distance(get_hash_grid_cell_pos(cell.index), nest.pos);
			if (nest_distance < nest.get_radius())
			{
				priority = TargetPriority::FoodOrNest;
				distance_to_goal = nest_distance;
			}
			else if (hash_grid.get_pheromone(cell) == Pheromone::Nest)
			{
				priority = TargetPriority::Pheromone;
				distance_to_goal = cell.pheromone_distance;
			}
		}
		// food and the nest replace each other, pheromones only closer ones
		const bool is_better = priority > target_priority || (target_slot.hasValue && priority == target_priority && (priority == TargetPriority::FoodOrNest || distance_to_goal < target_distance));
		if (!is_better) continue;
		target_slot = slot;
		target_priority = priority;
		target_distance = distance_to_goal;
	}
	if (let slot = target_slot)
	{
		ant.target_priority = target_priority;
		ant.target = get_hash_grid_cell_pos(hash_grid.cells[slot].index);
	}
}

// The ant puts down its food, and the nest grows to the level of its food. The level follows from the food that this
// ant's delivery made, by an atomic maximum, so that deliveries in the same dispatch can't skip a level.
void deliver_food(Nest* nest)
{
	Atomic<uint32_t>* food_amount = (Atomic<uint32_t>*)&nest.food_amount;
	const uint delivered_food_amount = food_amount.add(1) + 1;
	Atomic<int32_t>* level = (Atomic<int32_t>*)&nest.level;
	level.max(Nest::get_level(delivered_food_amount));
}

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void step_ants(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
	const uint ant_index = dispatch_thread_id.x;
	if (ant_index >= pc.ant_count) return;
	const float time = float(pc.step) * SIMULATION_TIME_STEP;
	vkte::Buffer<Ant> ants = vkte::get_buffer<Ant>(pc.ants);
	Nest* nest_pointer = vkte::get_buffer<Nest>(pc.nest).get_pointer();
	const Nest nest = nest_pointer[0];
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, time);
	const AntTime ant_time = AntTime(time, ant_index, pc.ant_count, 0.7982);
	Random rng = Random(ant_index + pc.ant_count * pc.step + 27349843);
	Ant ant = ants[ant_index];
	// now and then, the ant looks for a new target
	if (ant_time.chance(rng, 0.1, 0.05)) ant.target_priority = TargetPriority::None;
	look_for_target(ant, hash_grid, nest, ant_time, rng);
	// an ant without a target wanders to a random point nearby
	if (ant.target_priority == TargetPriority::None)
	{
		ant.target = ant.pos + rng.next_float2(-ANT_SEARCH_RADIUS, ANT_SEARCH_RADIUS);
		ant.target_priority = TargetPriority::Wander;
	}
	// an ant that reached its target wanders on in about the direction it went
	if (distance(ant.pos, ant.target) < (HASH_GRID_CELL_LENGTH / 2.0))
	{
		const float max_angle = radians(10.0);
		const float angle = rng.next_float(-max_angle, max_angle);
		const float2x2 rotation = float2x2(cos(angle), -sin(angle), sin(angle), cos(angle));
		const float target_distance = rng.next_float(ANT_SEARCH_RADIUS / 2.0, ANT_SEARCH_RADIUS);
		ant.target = ant.pos + mul(rotation, normalize(ant.dir)) * target_distance;
		ant.target_priority = TargetPriority::Wander;
	}
	ant.dir = normalize(ant.target - ant.pos + rng.next_float2(-0.01, 0.01)) * ANT_SPEED;
	ant.pos += ant.dir * SIMULATION_TIME_STEP;
	ant.distance_to_poi += ANT_SPEED * SIMULATION_TIME_STEP;

	// an ant at the world's bound turns back
	const float2 bounded_pos = clamp(ant.pos, -WORLD_BOUND, WORLD_BOUND);
	ant.dir = select(bounded_pos != ant.pos, -ant.dir * 0.1, ant.dir);
	ant.pos = bounded_pos;

	if (let slot = hash_grid.get_cell(get_hash_grid_pos(ant.pos)))
	{
		const HashGridCell cell = hash_grid.cells[slot];
		const float ant_nest_distance = distance(ant.pos, nest.pos);
		if (ant_nest_distance < nest.get_radius())
		{
			ant.distance_to_poi = ant_nest_distance;
			if (ant.has_food != 0)
			{
				ant.has_food = 0;
				ant.target_priority = TargetPriority::None;
				ant.pheromone_emit_scale = 2.0;
				deliver_food(nest_pointer);
			}
		}
		else
		{
			// a pheromone that leads where the ant comes from tells a shorter distance to it
			const Pheromone trail = ant.has_food != 0 ? Pheromone::Food : Pheromone::Nest;
			if (hash_grid.get_pheromone(cell) == trail && cell.pheromone_distance < ant.distance_to_poi - 2.0 * HASH_GRID_CELL_LENGTH) ant.distance_to_poi = cell.pheromone_distance;
		}
	}
	ants[ant_index] = ant;
}

// the ant leaves its pheromone in the cell, and takes food from it if it carries none
void update_cell(inout Ant ant, HashGrid hash_grid, uint slot, AntTime ant_time, inout Random rng)
{
	HashGridCell cell = hash_grid.cells[slot];
	const float emit_pheromone_probability = min(ant.pheromone_emit_scale / 10.0, 0.8);
	// the pheromone that leads where the ant comes from
	const Pheromone trail = ant.has_food != 0 ? Pheromone::Food : Pheromone::Nest;
	// an ant emits pheromones more likely the longer it saw none of its own kind
	const float step_length = ant.has_food != 0 ? 0.5 : 0.2;
	const float reset_probability = ant.has_food != 0 ? 0.4 : 0.5;
	if (hash_grid.get_pheromone(cell) == trail && ant_time.chance(rng, step_length, reset_probability)) ant.pheromone_emit_scale = 1.0;
	else if (ant_time.chance(rng, step_length, 0.5)) ant.pheromone_emit_scale += 1.0;
	if (ant.has_food == 0 && cell.food_amount > 0)
	{
		cell.food_amount--;
		ant.has_food = 1;
		ant.target_priority = TargetPriority::None;
		ant.distance_to_poi = 0.0;
		ant.pheromone_emit_scale = 2.0;
	}
	if (ant_time.chance(rng, 0.4, emit_pheromone_probability))
	{
		cell.pheromone = trail;
		cell.pheromone_time = hash_grid.time;
		cell.pheromone_distance = ant.distance_to_poi;
	}
	hash_grid.cells[slot] = cell;
	hash_grid.unlock_cell(slot);
}

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void update_hash_grid(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
	const uint ant_index = dispatch_thread_id.x;
	if (ant_index >= pc.ant_count) return;
	const float time = float(pc.step) * SIMULATION_TIME_STEP;
	vkte::Buffer<Ant> ants = vkte::get_buffer<Ant>(pc.ants);
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, time);
	const AntTime ant_time = AntTime(time, ant_index, pc.ant_count, 0.271);
	Random rng = Random(ant_index + pc.ant_count * pc.step + 43598763);
	Ant ant = ants[ant_index];
	const int2 hash_grid_pos = get_hash_grid_pos(ant.pos);
	// other ants may hold the cell's lock
	for (int attempt = 0; attempt < 32; attempt++)
	{
		if (let slot = hash_grid.try_acquire_cell(hash_grid_pos))
		{
			update_cell(ant, hash_grid, slot, ant_time, rng);
			break;
		}
	}
	ants[ant_index] = ant;
}

static const float2 QUAD_CORNERS[6] = {
	float2(-0.5, -0.5),
	float2( 0.5, -0.5),
	float2( 0.5,  0.5),
	float2(-0.5, -0.5),
	float2( 0.5,  0.5),
	float2(-0.5,  0.5)
};

static const float QUAD_SIZE = 0.02;

struct AntVertex
{
	float4 position : SV_Position;
	// the corner of the quad, from (0, 0) at its back to (1, 1) at its front
	float2 uv : TEXCOORD0;
	nointerpolation uint has_food : TEXCOORD1;
};

// one quad per ant instance, whose front corner points in the ant's direction
[shader("vertex")]
AntVertex vertex_main(uint vertex_id : SV_VertexID, uint instance_id : SV_InstanceID)
{
	const UniformBufferData ub = vkte::get_single_element_buffer<UniformBufferData>(pc.uniform_buffer);
	const Ant ant = vkte::get_buffer<Ant>(pc.ants)[instance_id];
	const float2 corner = QUAD_CORNERS[vertex_id];
	const float2 front = normalize(float2(1.0, 1.0));
	const float2 dir = normalize(ant.dir);
	const float cos_a = dot(front, dir);
	const float sin_a = front.x * dir.y - front.y * dir.x;
	const float2x2 rotation = float2x2(cos_a, -sin_a, sin_a, cos_a);
	const float2 pos = mul(rotation, corner * QUAD_SIZE) + ant.pos;

	AntVertex output;
	output.position = float4((2.0 * (pos - ub.range_min)) / (ub.range_max - ub.range_min) - 1.0, 0.0, 1.0);
	output.uv = corner + 0.5;
	output.has_food = ant.has_food;
	return output;
}

[shader("fragment")]
float4 fragment_main(AntVertex input) : SV_Target
{
	const UniformBufferData ub = vkte::get_single_element_buffer<UniformBufferData>(pc.uniform_buffer);
	// the ant's front corner has the direction marker's color
	float marker_weight = 0.0;
	if (input.uv.x + input.uv.y > 0.0)
	{
		const float angle_to_front = acos(dot(normalize(float2(1.0, 1.0)), normalize(input.uv)));
		marker_weight = 1.0 - smoothstep(radians(-15.0), radians(45.0), angle_to_front);
	}
	const float3 body_color = input.has_food != 0 ? ub.visualizations.ant_w_food_color : ub.visualizations.ant_wo_food_color;
	const float3 marker_color = input.has_food != 0 ? ub.visualizations.ant_w_food_dir_color : ub.visualizations.ant_wo_food_dir_color;
	return float4(lerp(body_color, marker_color, marker_weight), 1.0);
}
