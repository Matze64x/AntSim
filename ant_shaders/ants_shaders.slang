// The ants' shaders: the simulation step, in which they move (step_ants) and then lay trails and take food
// (update_hash_grid), and drawing them, a quad each (vertex_main, fragment_main).
import modules.ant;
import modules.hash_grid;
import modules.nest;
import modules.push_constants;
import modules.random;
import modules.uniform_buffer;
import modules.walls;
import vkte;

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

// Ants walk with a heading that drifts randomly. Ants searching for food lay the home trail, which tells their way home,
// and steer toward food or the food trail ahead that tells the shortest way to food, or, smelling none, away from the
// home trail: toward where it tells the longest way home or where there is none, so that they explore farther out and
// where no ant has been. Ants carrying food lay the food trail, which tells their way from the food, and steer toward the
// nest or the home trail ahead that tells the shortest way home, or where they believe the nest is if they smell none. A
// searching ant gives up the more likely the longer its way home is, and heads home like a carrying one, taking food that
// it comes across on the way. A trail tells the shortest way that any ant knew, and an ant takes a shorter way that its
// cell's trail tells, so trails lead along the shortest ways ants walked, around walls too, and any ant that strays onto
// a shorter way shortens them. Some ants explore for a while instead of following the trails (see
// BehaviorSettings::explorer_share).

// how fast the heading drifts randomly, in radians per square root of a second (a random walk of the heading)
static const float WANDER_STRENGTH = 2.0;
// how fast an ant turns toward a smell or the nest, in radians per second
static const float TURN_RATE = 6.0;
// an ant's antennae smell to the left and the right of its heading at this angle, and straight ahead
static const float ANTENNA_ANGLE = radians(40.0);
// how far ahead of the ant its antennae smell, in meters
static const float ANTENNA_LENGTH = 0.1;
// the error that path integration adds, in meters per square root of a meter walked (a random walk of the estimate)
static const float PATH_INTEGRATION_ERROR = 0.03;
// an ant that a wall blocks tries headings turned by multiples of this angle, the smallest first
static const float WALL_TURN_ANGLE = radians(30.0);

float2 rotate(float2 v, float angle)
{
	return mul(float2x2(cos(angle), -sin(angle), sin(angle), cos(angle)), v);
}

// What an antenna smells in the cells around a point: food, the nest, and the shortest ways to food and home that the
// trails tell; nothing in a wall.
struct Smell
{
	uint food_cell_count;
	// of these cells the one nearest to the point, if any
	float2 nearest_food_pos;
	uint nest_cell_count;
	float2 nearest_nest_pos;
	// float.maxValue if there is no such trail
	float food_distance;
	float home_distance;

	__init(HashGrid hash_grid, Walls walls, Nest nest, float2 pos)
	{
		food_cell_count = 0;
		nearest_food_pos = pos;
		nest_cell_count = 0;
		nearest_nest_pos = pos;
		food_distance = float.maxValue;
		home_distance = float.maxValue;
		const int2 center = get_hash_grid_pos(pos);
		if (walls.is_wall(center)) return;
		for (int y = -1; y <= 1; y++)
		{
			for (int x = -1; x <= 1; x++)
			{
				const int2 index = center + int2(x, y);
				const float2 cell_pos = get_hash_grid_cell_pos(index);
				if (all(index == get_hash_grid_pos(nest.pos))) add_cell(cell_pos, pos, nest_cell_count, nearest_nest_pos);
				const Optional<uint> slot = hash_grid.get_cell(index);
				if (!slot.hasValue) continue;
				const HashGridCell cell = hash_grid.cells[slot.value];
				if (cell.food_amount > 0) add_cell(cell_pos, pos, food_cell_count, nearest_food_pos);
				food_distance = min(food_distance, hash_grid.get_trail_distance(cell, Trail::Food));
				home_distance = min(home_distance, hash_grid.get_trail_distance(cell, Trail::Home));
			}
		}
	}

	static void add_cell(float2 cell_pos, float2 pos, inout uint cell_count, inout float2 nearest_pos)
	{
		if (cell_count == 0 || distance(cell_pos, pos) < distance(nearest_pos, pos)) nearest_pos = cell_pos;
		cell_count++;
	}

	// where the trail leads: food for the food trail, the nest for the home trail
	uint get_source_cell_count(Trail trail)
	{
		return trail == Trail::Food ? food_cell_count : nest_cell_count;
	}

	float2 get_nearest_source_pos(Trail trail)
	{
		return trail == Trail::Food ? nearest_food_pos : nearest_nest_pos;
	}

	float get_distance(Trail trail)
	{
		return trail == Trail::Food ? food_distance : home_distance;
	}
}

// what an ant's antennae smell to its left, ahead and to its right
struct Antennae
{
	Smell left;
	Smell ahead;
	Smell right;

	__init(Ant ant, HashGrid hash_grid, Walls walls, Nest nest)
	{
		left = Smell(hash_grid, walls, nest, ant.pos + rotate(ant.dir, ANTENNA_ANGLE) * ANTENNA_LENGTH);
		ahead = Smell(hash_grid, walls, nest, ant.pos + ant.dir * ANTENNA_LENGTH);
		right = Smell(hash_grid, walls, nest, ant.pos + rotate(ant.dir, -ANTENNA_ANGLE) * ANTENNA_LENGTH);
	}

	bool smell_trail(Trail trail)
	{
		return left.get_distance(trail) != float.maxValue || ahead.get_distance(trail) != float.maxValue || right.get_distance(trail) != float.maxValue;
	}

	// of the cells where the trail leads that the antennae smell, the one nearest to the ant, if any
	Optional<float2> get_nearest_source_pos(Trail trail, float2 ant_pos)
	{
		Optional<float2> nearest = none;
		for (int i = 0; i < 3; i++)
		{
			const Smell smell = i == 0 ? left : (i == 1 ? ahead : right);
			if (smell.get_source_cell_count(trail) == 0) continue;
			const float2 pos = smell.get_nearest_source_pos(trail);
			if (!nearest.hasValue || distance(pos, ant_pos) < distance(nearest.value, ant_pos)) nearest = pos;
		}
		return nearest;
	}

	// At most max_turn either way, toward the antenna that smells the shortest way the trail tells, or the longest if
	// away (where no trail counts as the longest way); none if it is straight ahead.
	float get_turn(Trail trail, bool away, float max_turn)
	{
		const float sign = away ? 1.0 : -1.0;
		const float left_score = sign * left.get_distance(trail);
		const float ahead_score = sign * ahead.get_distance(trail);
		const float right_score = sign * right.get_distance(trail);
		if (ahead_score >= left_score && ahead_score >= right_score) return 0.0;
		return left_score > right_score ? max_turn : -max_turn;
	}
}

// the turn, at most max_turn either way, toward a point
float turn_to(Ant ant, float2 point, float max_turn)
{
	const float2 to_point = point - ant.pos;
	const float angle = atan2(ant.dir.x * to_point.y - ant.dir.y * to_point.x, dot(ant.dir, to_point));
	return clamp(angle, -max_turn, max_turn);
}

// The heading closest to the ant's along which a step doesn't enter a wall, so that ants slide along walls: turned by
// ever larger multiples of WALL_TURN_ANGLE, to the side the ant turns to first; back the way it came if all are blocked.
float2 get_free_dir(Ant ant, Walls walls, float step_length, float side)
{
	for (int i = 0; i * WALL_TURN_ANGLE < float.getPi(); i++)
	{
		for (int j = 0; j < 2; j++)
		{
			const float angle = (j == 0 ? side : -side) * float(i) * WALL_TURN_ANGLE;
			const float2 dir = rotate(ant.dir, angle);
			if (!walls.is_wall(get_hash_grid_pos(ant.pos + dir * step_length))) return dir;
		}
	}
	return -ant.dir;
}

// an ant that leaves the nest or picks up food explores on its way with the chance BehaviorSettings::explorer_share
float get_exploration(BehaviorSettings behavior, inout Random rng)
{
	return rng.get_float() < behavior.explorer_share ? behavior.search_distance : 0.0;
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
	vkte::Buffer<Ant> ants = vkte::get_buffer<Ant>(pc.ants);
	Nest* nest_pointer = vkte::get_buffer<Nest>(pc.nest).get_pointer();
	const Nest nest = nest_pointer[0];
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, pc.step);
	const Walls walls = Walls(vkte::get_buffer<uint32_t>(pc.walls).get_pointer());
	Random rng = Random(ant_index + pc.ant_count * pc.step + 27349843);
	const BehaviorSettings behavior = vkte::get_single_element_buffer<UniformBufferData>(pc.uniform_buffer).behavior;
	Ant ant = ants[ant_index];
	// a new ant leaves the nest in a random direction
	if (all(ant.dir == 0.0))
	{
		ant.pos = nest.pos;
		ant.dir = rotate(float2(1.0, 0.0), rng.get_float(0.0, 2.0 * float.getPi()));
		ant.nest_estimate = nest.pos;
		ant.exploration_left = get_exploration(behavior, rng);
	}

	// see BehaviorSettings::search_distance
	const float give_up_chance = 2.0 * ant.distance_walked * ANT_SPEED * SIMULATION_TIME_STEP / (behavior.search_distance * behavior.search_distance);
	if (ant.state == AntState::Search && rng.get_float() < give_up_chance) ant.state = AntState::GiveUp;
	const bool heads_home = ant.state != AntState::Search;

	const float max_turn = TURN_RATE * SIMULATION_TIME_STEP;
	float turn = rng.get_float(-1.0, 1.0) * WANDER_STRENGTH * sqrt(SIMULATION_TIME_STEP);
	// searching ants follow the food trail, ants heading home the home trail
	const Antennae antennae = Antennae(ant, hash_grid, walls, nest);
	const Trail trail = heads_home ? Trail::Home : Trail::Food;
	// an ant that smells where its trail leads, food or the nest, heads straight there
	const Optional<float2> source_pos = antennae.get_nearest_source_pos(trail, ant.pos);
	if (source_pos.hasValue) turn += turn_to(ant, source_pos.value, max_turn);
	// an explorer just walks randomly
	else if (ant.exploration_left <= 0.0)
	{
		if (antennae.smell_trail(trail)) turn += antennae.get_turn(trail, false, max_turn);
		else if (heads_home) turn += turn_to(ant, ant.nest_estimate, max_turn);
		else turn += antennae.get_turn(Trail::Home, true, max_turn);
	}
	// an ant heading home that smells the nest knows where it is
	if (heads_home && source_pos.hasValue) ant.nest_estimate = nest.pos;
	ant.dir = normalize(rotate(ant.dir, turn));
	const float step_length = ANT_SPEED * SIMULATION_TIME_STEP;
	// an ant in a wall (painted onto it) walks out of it in any direction
	if (!walls.is_wall(get_hash_grid_pos(ant.pos))) ant.dir = get_free_dir(ant, walls, step_length, turn >= 0.0 ? 1.0 : -1.0);
	const float2 next_pos = ant.pos + ant.dir * step_length;
	// unless walls enclose the ant
	if (!walls.is_wall(get_hash_grid_pos(next_pos)) || walls.is_wall(get_hash_grid_pos(ant.pos)))
	{
		ant.pos = next_pos;
		ant.distance_walked += step_length;
		ant.exploration_left = max(ant.exploration_left - step_length, 0.0);
	}
	ant.nest_estimate += rng.get_float2_in_disk() * PATH_INTEGRATION_ERROR * sqrt(step_length);

	// the nest is a point, its cell, so that all ways to it meet there and ants leaving it find any of them
	const bool in_nest = all(get_hash_grid_pos(ant.pos) == get_hash_grid_pos(nest.pos));
	if (in_nest)
	{
		ant.nest_estimate = nest.pos;
		ant.distance_walked = 0.0;
	}
	// an ant back home searches again, from where it came
	if (in_nest && heads_home)
	{
		if (ant.state == AntState::CarryFood) deliver_food(nest_pointer);
		ant.state = AntState::Search;
		ant.dir = -ant.dir;
		ant.exploration_left = get_exploration(behavior, rng);
	}
	ants[ant_index] = ant;
}

// An ant takes a shorter way back that its cell's trail tells and lays its trail there, the food trail if it carries food,
// else the home trail. An ant carrying no food takes food from the cell if it has any and turns back home. Other ants may
// update the same cell concurrently; cells have no locks, since every ant in a cell gets to act each step.
[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void update_hash_grid(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
	const uint ant_index = dispatch_thread_id.x;
	if (ant_index >= pc.ant_count) return;
	vkte::Buffer<Ant> ants = vkte::get_buffer<Ant>(pc.ants);
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, pc.step);
	const BehaviorSettings behavior = vkte::get_single_element_buffer<UniformBufferData>(pc.uniform_buffer).behavior;
	Random rng = Random(ant_index + pc.ant_count * pc.step + 43598763);
	Ant ant = ants[ant_index];
	const int2 hash_grid_pos = get_hash_grid_pos(ant.pos);
	// the trail that leads back where the ant came from
	const Trail trail = ant.state == AntState::CarryFood ? Trail::Food : Trail::Home;
	const Optional<uint> slot = hash_grid.get_cell(hash_grid_pos);
	// The cell's trail tells the way from anywhere in the cell, which may be up to the cell's diagonal shorter than from
	// where the ant is. Without that margin, an ant would take the slightly shorter way that it laid itself a step before in
	// the same cell, and its way would grow only as fast as trails age instead of as fast as it walks.
	if (slot.hasValue) ant.distance_walked = min(ant.distance_walked, hash_grid.get_trail_distance(hash_grid.cells[slot.value], trail) + sqrt(2.0) * HASH_GRID_CELL_LENGTH);
	if (ant.distance_walked <= MAX_TRAIL_DISTANCE) hash_grid.lay_trail(hash_grid_pos, trail, ant.distance_walked);
	if (ant.state != AntState::CarryFood)
	{
		if (slot.hasValue && hash_grid.take_food(slot.value))
		{
			ant.state = AntState::CarryFood;
			ant.dir = -ant.dir;
			ant.distance_walked = 0.0;
			ant.exploration_left = get_exploration(behavior, rng);
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
	nointerpolation uint carries_food : TEXCOORD1;
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
	output.carries_food = ant.state == AntState::CarryFood ? 1 : 0;
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
	const float3 body_color = input.carries_food != 0 ? ub.visualizations.ant_w_food_color : ub.visualizations.ant_wo_food_color;
	const float3 marker_color = input.carries_food != 0 ? ub.visualizations.ant_w_food_dir_color : ub.visualizations.ant_wo_food_dir_color;
	return float4(lerp(body_color, marker_color, marker_weight), 1.0);
}
