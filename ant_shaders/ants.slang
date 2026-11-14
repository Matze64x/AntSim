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

// Ants walk with a heading that drifts randomly; ants that carry no food steer toward the strongest smell of food and
// food trail ahead, and ants that carry food steer toward where they believe the nest is, laying the food trail.

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
// food smells stronger than any trail around an antenna, so that ants on a trail turn to food next to it
static const float FOOD_SCENT = 10.0;
// how far ants may go from the origin along each axis
static const float WORLD_BOUND = 100.0;

float2 rotate(float2 v, float angle)
{
	return mul(float2x2(cos(angle), -sin(angle), sin(angle), cos(angle)), v);
}

// The smell of food and food trail around a point: of the cells around the point's cell, food or the trail's freshness.
// Fresher trails smell stronger.
float smell(HashGrid hash_grid, float2 pos)
{
	const int2 center = get_hash_grid_pos(pos);
	float strength = 0.0;
	for (int y = -1; y <= 1; y++)
	{
		for (int x = -1; x <= 1; x++)
		{
			if (let slot = hash_grid.get_cell(center + int2(x, y)))
			{
				const HashGridCell cell = hash_grid.cells[slot];
				strength += cell.food_amount > 0 ? FOOD_SCENT : hash_grid.get_food_trail_freshness(cell);
			}
		}
	}
	return strength;
}

// the turn, at most max_turn either way, toward the stronger smell of the antennae, none if straight ahead smells strongest
float turn_to_smell(Ant ant, HashGrid hash_grid, float max_turn)
{
	const float left = smell(hash_grid, ant.pos + rotate(ant.dir, ANTENNA_ANGLE) * ANTENNA_LENGTH);
	const float ahead = smell(hash_grid, ant.pos + ant.dir * ANTENNA_LENGTH);
	const float right = smell(hash_grid, ant.pos + rotate(ant.dir, -ANTENNA_ANGLE) * ANTENNA_LENGTH);
	if (ahead >= left && ahead >= right) return 0.0;
	return left > right ? max_turn : -max_turn;
}

// the turn, at most max_turn either way, toward a point
float turn_to(Ant ant, float2 point, float max_turn)
{
	const float2 to_point = point - ant.pos;
	const float angle = atan2(ant.dir.x * to_point.y - ant.dir.y * to_point.x, dot(ant.dir, to_point));
	return clamp(angle, -max_turn, max_turn);
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
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, float(pc.step) * SIMULATION_TIME_STEP);
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
	turn += ant.has_food != 0 ? turn_to(ant, ant.nest_estimate, max_turn) : turn_to_smell(ant, hash_grid, max_turn);
	ant.dir = normalize(rotate(ant.dir, turn));
	const float step_length = ANT_SPEED * SIMULATION_TIME_STEP;
	ant.pos += ant.dir * step_length;
	ant.nest_estimate += rng.get_float2_in_disk() * PATH_INTEGRATION_ERROR * sqrt(step_length);

	// an ant at the world's bound turns back
	const float2 bounded_pos = clamp(ant.pos, -WORLD_BOUND, WORLD_BOUND);
	if (any(bounded_pos != ant.pos)) ant.dir = -ant.dir;
	ant.pos = bounded_pos;

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
	const HashGrid hash_grid = HashGrid(vkte::get_buffer<HashGridCell>(pc.hash_grid).get_pointer(), pc.hash_grid_capacity, float(pc.step) * SIMULATION_TIME_STEP);
	Ant ant = ants[ant_index];
	const int2 hash_grid_pos = get_hash_grid_pos(ant.pos);
	if (ant.has_food != 0)
	{
		hash_grid.lay_food_trail(hash_grid_pos);
	}
	else if (let slot = hash_grid.get_cell(hash_grid_pos))
	{
		if (hash_grid.take_food(slot))
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
