import include.hash_grid;
import include.nest;
import include.random;
import include.walls;
import shared.ant;
import shared.hash_grid;
import shared.nest;
import shared.push_constants;
import shared.uniform_buffer;
import vkte;

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

// Ants walk with a heading that drifts randomly; ants that carry no food steer toward the strongest smell of food or food
// trail ahead, and ants that carry food steer toward where they believe the nest is, laying the food trail. Since busy
// trails grow stronger and unused ones fade, the colony converges on short ones.

// in meters per second
static const float ANT_SPEED = 0.2;
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
// how far beyond the nest's edge ants smell the nest, in meters, which corrects their estimate of where it is
static const float NEST_SCENT_DISTANCE = 0.2;
// an ant that a wall blocks tries headings turned by multiples of this angle, the smallest first
static const float WALL_TURN_ANGLE = radians(30.0);

float2 rotate(float2 v, float angle)
{
	return mul(float2x2(cos(angle), -sin(angle), sin(angle), cos(angle)), v);
}

// what an antenna smells in the cells around a point; nothing in a wall
struct Smell
{
	// the cells with food
	uint food_cell_count;
	float food_trail;

	__init(HashGrid hash_grid, Walls walls, float2 pos)
	{
		food_cell_count = 0;
		food_trail = 0.0;
		const int2 center = get_hash_grid_pos(pos);
		if (walls.is_wall(center)) return;
		for (int y = -1; y <= 1; y++)
		{
			for (int x = -1; x <= 1; x++)
			{
				const Optional<uint> slot = hash_grid.get_cell(center + int2(x, y));
				if (slot.hasValue)
				{
					const HashGridCell cell = hash_grid.cells[slot.value];
					if (cell.food_amount > 0) food_cell_count++;
					food_trail += hash_grid.get_food_trail(cell);
				}
			}
		}
	}

	// food smells stronger than any trail, so that ants on a trail turn to food next to it
	bool is_stronger_than(Smell other)
	{
		return food_cell_count != other.food_cell_count ? food_cell_count > other.food_cell_count : food_trail > other.food_trail;
	}
}

// the turn, at most max_turn either way, toward the stronger smell of the antennae, none if straight ahead smells strongest
float turn_to_smell(Ant ant, HashGrid hash_grid, Walls walls, float max_turn)
{
	const Smell left = Smell(hash_grid, walls, ant.pos + rotate(ant.dir, ANTENNA_ANGLE) * ANTENNA_LENGTH);
	const Smell ahead = Smell(hash_grid, walls, ant.pos + ant.dir * ANTENNA_LENGTH);
	const Smell right = Smell(hash_grid, walls, ant.pos + rotate(ant.dir, -ANTENNA_ANGLE) * ANTENNA_LENGTH);
	if (!left.is_stronger_than(ahead) && !right.is_stronger_than(ahead)) return 0.0;
	return left.is_stronger_than(right) ? max_turn : -max_turn;
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
		ant.dir = rotate(float2(1.0, 0.0), rng.get_float(0.0, 2.0 * float.getPi()));
		ant.nest_estimate = nest.pos;
	}

	const float max_turn = TURN_RATE * SIMULATION_TIME_STEP;
	float turn = rng.get_float(-1.0, 1.0) * WANDER_STRENGTH * sqrt(SIMULATION_TIME_STEP);
	turn += ant.has_food != 0 ? turn_to(ant, ant.nest_estimate, max_turn) : turn_to_smell(ant, hash_grid, walls, max_turn);
	ant.dir = normalize(rotate(ant.dir, turn));
	const float step_length = ANT_SPEED * SIMULATION_TIME_STEP;
	// an ant in a wall (painted onto it) walks out of it in any direction
	if (!walls.is_wall(get_hash_grid_pos(ant.pos))) ant.dir = get_free_dir(ant, walls, step_length, turn >= 0.0 ? 1.0 : -1.0);
	const float2 next_pos = ant.pos + ant.dir * step_length;
	// unless walls enclose the ant
	if (!walls.is_wall(get_hash_grid_pos(next_pos)) || walls.is_wall(get_hash_grid_pos(ant.pos))) ant.pos = next_pos;
	ant.nest_estimate += rng.get_float2_in_disk() * PATH_INTEGRATION_ERROR * sqrt(step_length);

	const float nest_distance = distance(ant.pos, nest.pos);
	if (nest_distance < nest.get_radius() + NEST_SCENT_DISTANCE) ant.nest_estimate = nest.pos;
	// an ant that brought food home turns back to where it found it
	if (nest_distance < nest.get_radius() && ant.has_food != 0)
	{
		ant.has_food = 0;
		ant.dir = -ant.dir;
		deliver_food(nest_pointer);
	}
	ants[ant_index] = ant;
}

// An ant carrying food lays the food trail in its cell; an ant carrying none takes food from its cell if it has any and
// turns back home. Other ants may update the same cell concurrently; cells have no locks, since every ant in a cell gets
// to act each step.
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
		// the seconds the ant spends in the cell this step
		hash_grid.lay_food_trail(hash_grid_pos, SIMULATION_TIME_STEP);
	}
	else
	{
		const Optional<uint> slot = hash_grid.get_cell(hash_grid_pos);
		if (slot.hasValue && hash_grid.take_food(slot.value))
		{
			ant.has_food = 1;
			ant.dir = -ant.dir;
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
