import shared.hash_grid;

int2 get_hash_grid_pos(float2 position)
{
	return int2(floor(position / HASH_GRID_CELL_LENGTH));
}

// the center of a cell
float2 get_hash_grid_cell_pos(int2 hash_grid_pos)
{
	return float2(hash_grid_pos) * HASH_GRID_CELL_LENGTH + HASH_GRID_CELL_LENGTH / 2.0;
}

// http://burtleburtle.net/bob/hash/integer.html
uint hash_jenkins32(uint a)
{
	a = (a + 0x7ed55d16) + (a << 12);
	a = (a ^ 0xc761c23c) ^ (a >> 19);
	a = (a + 0x165667b1) + (a << 5);
	a = (a + 0xd3a2646c) ^ (a << 9);
	a = (a + 0xfd7046c5) + (a << 3);
	a = (a ^ 0xb55a4f09) ^ (a >> 16);
	return a;
}

// a grid position as the key that identifies its cell; 16 bits per axis, which hold the positions within the world's bound
uint get_hash_grid_key(int2 index)
{
	return (uint(index.x) & 0xffffu) | (uint(index.y) << 16u);
}

extension HashGridCell
{
	Trail get_trail(Pheromone pheromone)
	{
		return pheromone == Pheromone::Food ? food_trail : nest_trail;
	}
}

// The hash grid's cells, through a pointer, so that writing a member writes only that member. Each grid position has
// one slot; a cell holds its position's data while it is alive, has food or a pheromone that hasn't expired. A slot whose
// cell isn't alive is free for any position, and a position whose slot holds another position's living cell is
// wasteland, where nothing can be laid.
struct HashGrid
{
	HashGridCell* cells;
	uint capacity;
	// the simulated time, which pheromones expire by
	float time;

	bool is_fresh(Trail trail)
	{
		return time < trail.expiry_time;
	}

	// 1 when the pheromone was just laid, 0 when it expires
	float get_freshness(Trail trail)
	{
		return (trail.expiry_time - time) / PHEROMONE_LIFETIME;
	}

	bool is_alive(HashGridCell cell)
	{
		return cell.food_amount > 0 || is_fresh(cell.nest_trail) || is_fresh(cell.food_trail);
	}

	uint get_slot(int2 index)
	{
		return (hash_jenkins32(uint(index.x) ^ 0xcf5ae914u) ^ hash_jenkins32(uint(index.y))) % capacity;
	}

	// the slot of the index's cell, none if it has none
	Optional<uint> get_cell(int2 index)
	{
		const uint slot = get_slot(index);
		if (cells[slot].key != get_hash_grid_key(index) || !is_alive(cells[slot])) return none;
		return slot;
	}

	// The slot of the index's cell, which takes the slot if its cell isn't alive; none if the index is wasteland. A cell
	// that isn't alive has neither food nor a fresh pheromone, so taking it needs no clearing.
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

	// lays the pheromone in the index's cell unless the index is wasteland
	void lay_pheromone(int2 index, Pheromone pheromone, float distance)
	{
		if (let slot = claim_cell(index))
		{
			Trail* trail = pheromone == Pheromone::Food ? &cells[slot].food_trail : &cells[slot].nest_trail;
			trail.expiry_time = time + PHEROMONE_LIFETIME;
			trail.distance = distance;
		}
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
