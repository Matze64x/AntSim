#pragma once
#include "modules/common.slang"
#ifdef __SLANG__
import modules.ant;
import modules.push_constants;
#else // __SLANG__
#include "modules/ant.slang"
#endif // __SLANG__

// in meters
AS_CONSTANT float HASH_GRID_CELL_LENGTH = 0.04f;

// The way that a trail tells grows by this many meters per second. Slower than ants walk, so that along an ant's path the
// older part, nearer to where it came from, still tells the shorter way.
AS_CONSTANT float TRAIL_AGING_SPEED = ANT_SPEED / 2.0f;
// ants ignore trails that tell a longer way than this, in meters
AS_CONSTANT float MAX_TRAIL_DISTANCE = 50.0f;
// Cells store their trails as of a trail epoch, which this many steps make up; after the last one, a pass ages every
// cell's trails to the next epoch. So aging needs no pass per step.
AS_CONSTANT uint32_t TRAIL_EPOCH_STEP_COUNT = 600;

// A cell is free unless it has food or a trail that ants smell. Ants update cells concurrently without locks: they take
// food and lay trails atomically.
struct HashGridCell
{
	// the cell's grid position, packed by get_hash_grid_key()
	uint32_t key;
	int32_t food_amount;
	// The shortest way from the food that ants carrying food knew in the cell (the food trail), and the shortest way home
	// that ants searching for food knew (the home trail), each aged since by TRAIL_AGING_SPEED. As of the current trail
	// epoch's end, and stored as the complement of the distance's bits, so that 0 (the start) means none and an atomic
	// maximum keeps the shortest way (HashGrid::get_trail_distance() gives the current distance).
	uint32_t food_trail;
	uint32_t home_trail;
};

// http://burtleburtle.net/bob/hash/integer.html
AS_FUNCTION uint32_t hash_jenkins32(uint32_t a)
{
	a = (a + 0x7ed55d16u) + (a << 12u);
	a = (a ^ 0xc761c23cu) ^ (a >> 19u);
	a = (a + 0x165667b1u) + (a << 5u);
	a = (a + 0xd3a2646cu) ^ (a << 9u);
	a = (a + 0xfd7046c5u) + (a << 3u);
	a = (a ^ 0xb55a4f09u) ^ (a >> 16u);
	return a;
}

// a grid position as the key that identifies its cell; 16 bits per axis, which hold the positions within the world's bound
AS_FUNCTION uint32_t get_hash_grid_key(int2 index)
{
	return (uint32_t(index.x) & 0xffffu) | (uint32_t(index.y) << 16u);
}

// the slot of a grid position in a hash grid with the capacity
AS_FUNCTION uint32_t get_hash_grid_slot(int2 index, uint32_t capacity)
{
	return (hash_jenkins32(uint32_t(index.x) ^ 0xcf5ae914u) ^ hash_jenkins32(uint32_t(index.y))) % capacity;
}

#ifdef __SLANG__

int2 get_hash_grid_pos(float2 position)
{
	return int2(floor(position / HASH_GRID_CELL_LENGTH));
}

// the center of a cell
float2 get_hash_grid_cell_pos(int2 hash_grid_pos)
{
	return float2(hash_grid_pos) * HASH_GRID_CELL_LENGTH + HASH_GRID_CELL_LENGTH / 2.0;
}

// The bits of a non-negative distance order like the distances, so their complement orders reversely and isn't 0.
uint encode_trail_distance(float distance)
{
	return ~asuint(distance);
}

float decode_trail_distance(uint trail)
{
	return asfloat(~trail);
}

// the food trail leads to food, the home trail to the nest
enum class Trail
{
	Food,
	Home
}

// The hash grid's cells, through a pointer, so that writing a member writes only that member. Each grid position has
// one slot; a cell holds its position's data while it is alive, has food or a trail that ants smell. A slot whose cell
// isn't alive is free for any position, and a position whose slot holds another position's living cell is wasteland,
// where nothing can be laid.
struct HashGrid
{
	HashGridCell* cells;
	uint capacity;
	// how much a trail will still age until the current trail epoch ends, which turns the stored trails into current ones
	float trail_aging;

	// of the simulation step
	__init(HashGridCell* cells, uint capacity, uint step)
	{
		this.cells = cells;
		this.capacity = capacity;
		const uint epoch_step = step % TRAIL_EPOCH_STEP_COUNT;
		trail_aging = TRAIL_AGING_SPEED * float(TRAIL_EPOCH_STEP_COUNT - epoch_step) * SIMULATION_TIME_STEP;
	}

	// the way to food or home that the cell's trail tells, float.maxValue if it has none that ants smell
	float get_trail_distance(HashGridCell cell, Trail trail)
	{
		const uint stored = trail == Trail::Food ? cell.food_trail : cell.home_trail;
		if (stored == 0) return float.maxValue;
		const float distance = decode_trail_distance(stored) - trail_aging;
		return distance <= MAX_TRAIL_DISTANCE ? distance : float.maxValue;
	}

	bool has_trail(HashGridCell cell, Trail trail)
	{
		return get_trail_distance(cell, trail) != float.maxValue;
	}

	bool is_alive(HashGridCell cell)
	{
		return cell.food_amount > 0 || has_trail(cell, Trail::Food) || has_trail(cell, Trail::Home);
	}

	uint get_slot(int2 index)
	{
		return get_hash_grid_slot(index, capacity);
	}

	// the slot of the index's cell, none if it has none
	Optional<uint> get_cell(int2 index)
	{
		const uint slot = get_slot(index);
		if (cells[slot].key != get_hash_grid_key(index) || !is_alive(cells[slot])) return none;
		return slot;
	}

	// The slot of the index's cell, which takes the slot if its cell isn't alive; none if the index is wasteland. A cell
	// that isn't alive has no food and at most trails that ants don't smell, which the new index may as well keep.
	Optional<uint> claim_cell(int2 index)
	{
		const uint slot = get_slot(index);
		const uint key = get_hash_grid_key(index);
		Atomic<uint32_t>* slot_key = (Atomic<uint32_t>*)&cells[slot].key;
		const uint previous_key = slot_key.load();
		if (previous_key == key) return slot;
		if (is_alive(cells[slot])) return none;
		// another thread may take the slot first, for this index or another
		const uint taken_key = slot_key.compareExchange(previous_key, key);
		if (taken_key == previous_key || taken_key == key) return slot;
		return none;
	}

	// the trail in the index's cell tells at most the distance unless the index is wasteland
	void lay_trail(int2 index, Trail trail, float distance)
	{
		const Optional<uint> slot = claim_cell(index);
		if (!slot.hasValue) return;
		uint32_t* stored = trail == Trail::Food ? &cells[slot.value].food_trail : &cells[slot.value].home_trail;
		((Atomic<uint32_t>*)stored).max(encode_trail_distance(distance + trail_aging));
	}

	// takes one food from the slot's cell if it has any left
	bool take_food(uint slot)
	{
		if (cells[slot].food_amount <= 0) return false;
		Atomic<int32_t>* food_amount = (Atomic<int32_t>*)&cells[slot].food_amount;
		if (food_amount.add(-1) > 0) return true;
		// other ants took the last food meanwhile
		food_amount.add(1);
		return false;
	}
}

#endif // __SLANG__
