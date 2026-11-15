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
// and steer toward the strongest smell of food or food trail ahead; ants carrying food lay the food trail and steer toward
// the home trail ahead that tells the shortest way home, or where they believe the nest is if they smell none. Home
// trails tell the shortest way any searching ant knew, so they lead home along the ways ants walked, around walls too.
// An ant lays the food trail the weaker the farther it walked from the food, so that it leads there; since busy food
// trails grow stronger and unused ones fade, the colony converges on short ones.

// which trail an ant follows: the food trail leads to food, the home trail to the nest
enum class Trail
{
	Food,
	Home
}

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
// An ant lays the food trail half as strong for every this many meters it walked from the food. Shorter than the way an
// ant walks while the trail fades to half (ANT_SPEED * FOOD_TRAIL_HALF_LIFE), so that along an ant's path the older
// part, nearer to the food, stays stronger than the fresher part: the trail leads to the food, not after the ant.
static const float FOOD_TRAIL_HALF_DISTANCE = ANT_SPEED * FOOD_TRAIL_HALF_LIFE / 2.0;
// an ant that a wall blocks tries headings turned by multiples of this angle, the smallest first
static const float WALL_TURN_ANGLE = radians(30.0);

float2 rotate(float2 v, float angle)
{
	return mul(float2x2(cos(angle), -sin(angle), sin(angle), cos(angle)), v);
}

// What an antenna smells of a trail in the cells around a point, and of where the trail leads, food for the food trail
// and the nest for the home trail; nothing in a wall.
struct Smell
{
	// the cells with food, or in the nest
	uint source_cell_count;
	// of these cells the one nearest to the point, if any
	float2 nearest_source_pos;
	bool has_trail;
	// the larger the stronger: the food trail's amount, or the negated shortest way home that the home trail tells
	float trail_strength;

	__init(HashGrid hash_grid, Walls walls, Nest nest, float2 pos, Trail trail)
	{
		source_cell_count = 0;
		nearest_source_pos = pos;
		has_trail = false;
		trail_strength = trail == Trail::Food ? 0.0 : -float.maxValue;
		const int2 center = get_hash_grid_pos(pos);
		if (walls.is_wall(center)) return;
		for (int y = -1; y <= 1; y++)
		{
			for (int x = -1; x <= 1; x++)
			{
				const int2 index = center + int2(x, y);
				if (trail == Trail::Home && distance(get_hash_grid_cell_pos(index), nest.pos) < nest.get_radius()) add_source_cell(index, pos);
				const Optional<uint> slot = hash_grid.get_cell(index);
				if (slot.hasValue)
				{
					const HashGridCell cell = hash_grid.cells[slot.value];
					if (trail == Trail::Food)
					{
						if (cell.food_amount > 0) add_source_cell(index, pos);
						has_trail = has_trail || hash_grid.has_food_trail(cell);
						trail_strength += hash_grid.get_food_trail(cell);
					}
					else
					{
						has_trail = has_trail || hash_grid.has_home_trail(cell);
						trail_strength = max(trail_strength, -hash_grid.get_home_distance(cell));
					}
				}
			}
		}
	}

	[mutating] void add_source_cell(int2 index, float2 pos)
	{
		const float2 cell_pos = get_hash_grid_cell_pos(index);
		if (source_cell_count == 0 || distance(cell_pos, pos) < distance(nearest_source_pos, pos)) nearest_source_pos = cell_pos;
		source_cell_count++;
	}

	bool is_empty()
	{
		return source_cell_count == 0 && !has_trail;
	}

	// food or the nest smells stronger than any trail, so that ants on a trail turn to it when they pass it
	bool is_stronger_than(Smell other)
	{
		return source_cell_count != other.source_cell_count ? source_cell_count > other.source_cell_count : trail_strength > other.trail_strength;
	}
}

// what an ant's antennae smell to its left, ahead and to its right
struct Antennae
{
	Smell left;
	Smell ahead;
	Smell right;

	__init(Ant ant, HashGrid hash_grid, Walls walls, Nest nest, Trail trail)
	{
		left = Smell(hash_grid, walls, nest, ant.pos + rotate(ant.dir, ANTENNA_ANGLE) * ANTENNA_LENGTH, trail);
		ahead = Smell(hash_grid, walls, nest, ant.pos + ant.dir * ANTENNA_LENGTH, trail);
		right = Smell(hash_grid, walls, nest, ant.pos + rotate(ant.dir, -ANTENNA_ANGLE) * ANTENNA_LENGTH, trail);
	}

	bool is_empty()
	{
		return left.is_empty() && ahead.is_empty() && right.is_empty();
	}

	// of the cells with food, or in the nest, that the antennae smell, the one nearest to the ant, if any
	Optional<float2> get_nearest_source_pos(float2 ant_pos)
	{
		Optional<float2> nearest = none;
		for (int i = 0; i < 3; i++)
		{
			const Smell smell = i == 0 ? left : (i == 1 ? ahead : right);
			if (smell.source_cell_count == 0) continue;
			if (!nearest.hasValue || distance(smell.nearest_source_pos, ant_pos) < distance(nearest.value, ant_pos)) nearest = smell.nearest_source_pos;
		}
		return nearest;
	}

	// at most max_turn either way, toward the stronger smell, none if straight ahead smells strongest
	float get_turn(float max_turn)
	{
		if (!left.is_stronger_than(ahead) && !right.is_stronger_than(ahead)) return 0.0;
		return left.is_stronger_than(right) ? max_turn : -max_turn;
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
	Ant ant = ants[ant_index];
	// a new ant leaves the nest in a random direction
	if (all(ant.dir == 0.0))
	{
		ant.pos = nest.pos;
		ant.dir = rotate(float2(1.0, 0.0), rng.get_float(0.0, 2.0 * float.getPi()));
		ant.nest_estimate = nest.pos;
	}

	const float max_turn = TURN_RATE * SIMULATION_TIME_STEP;
	float turn = rng.get_float(-1.0, 1.0) * WANDER_STRENGTH * sqrt(SIMULATION_TIME_STEP);
	// searching ants follow the food trail, ants carrying food the home trail
	const Antennae antennae = Antennae(ant, hash_grid, walls, nest, ant.has_food != 0 ? Trail::Home : Trail::Food);
	// an ant that smells where its trail leads, food or the nest, heads straight there
	const Optional<float2> source_pos = antennae.get_nearest_source_pos(ant.pos);
	if (source_pos.hasValue) turn += turn_to(ant, source_pos.value, max_turn);
	else if (ant.has_food != 0 && antennae.is_empty()) turn += turn_to(ant, ant.nest_estimate, max_turn);
	else turn += antennae.get_turn(max_turn);
	// an ant carrying food that smells the nest knows where it is
	if (ant.has_food != 0 && source_pos.hasValue) ant.nest_estimate = nest.pos;
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
	}
	ant.nest_estimate += rng.get_float2_in_disk() * PATH_INTEGRATION_ERROR * sqrt(step_length);

	const bool in_nest = distance(ant.pos, nest.pos) < nest.get_radius();
	if (in_nest)
	{
		ant.nest_estimate = nest.pos;
		ant.distance_walked = 0.0;
	}
	// an ant that brought food home turns back to where it found it
	if (in_nest && ant.has_food != 0)
	{
		ant.has_food = 0;
		ant.dir = -ant.dir;
		deliver_food(nest_pointer);
	}
	ants[ant_index] = ant;
}

// An ant carrying food lays the food trail in its cell. An ant searching for food takes a shorter way home that its cell's
// home trail tells, lays the home trail, and takes food from the cell if it has any and turns back home. Other ants may
// update the same cell concurrently; cells have no locks, since every ant in a cell gets to act each step.
[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void update_hash_grid(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
	const uint ant_index = dispatch_thread_id.x;
	if (ant_index >= pc.ant_count) return;
	vkte::Buffer<Ant> ants = vkte::get_buffer<Ant>(pc.ants);
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, pc.step);
	Ant ant = ants[ant_index];
	const int2 hash_grid_pos = get_hash_grid_pos(ant.pos);
	if (ant.has_food != 0)
	{
		// the seconds the ant spends in the cell this step, weakened by the distance it walked from the food
		hash_grid.lay_food_trail(hash_grid_pos, SIMULATION_TIME_STEP * exp2(-ant.distance_walked / FOOD_TRAIL_HALF_DISTANCE));
	}
	else
	{
		const Optional<uint> slot = hash_grid.get_cell(hash_grid_pos);
		if (slot.hasValue) ant.distance_walked = min(ant.distance_walked, hash_grid.get_home_distance(hash_grid.cells[slot.value]));
		if (ant.distance_walked <= MAX_HOME_DISTANCE) hash_grid.lay_home_trail(hash_grid_pos, ant.distance_walked);
		if (slot.hasValue && hash_grid.take_food(slot.value))
		{
			ant.has_food = 1;
			ant.dir = -ant.dir;
			ant.distance_walked = 0.0;
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
