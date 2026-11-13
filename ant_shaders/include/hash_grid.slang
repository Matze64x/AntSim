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

// The hash grid's cells, through a pointer, so that writing a member writes only that member. Each grid position has
// one slot; a position whose slot holds another one has no cell. A cell holds its position's data while it is alive, has
// food or a pheromone that hasn't expired; a slot whose cell isn't alive is free for any position.
struct HashGrid
{
	HashGridCell* cells;
	uint capacity;
	// the simulated time, which pheromones expire by
	float time;

	// none once the pheromone expired
	Pheromone get_pheromone(HashGridCell cell)
	{
		return time - cell.pheromone_time <= PHEROMONE_LIFETIME ? cell.pheromone : Pheromone::None;
	}

	// 1 when the pheromone was just laid, 0 when it expires
	float get_pheromone_freshness(HashGridCell cell)
	{
		return 1.0 - (time - cell.pheromone_time) / PHEROMONE_LIFETIME;
	}

	bool is_alive(HashGridCell cell)
	{
		return cell.food_amount > 0 || get_pheromone(cell) != Pheromone::None;
	}

	uint get_slot(int2 index)
	{
		return (hash_jenkins32(uint(index.x) ^ 0xcf5ae914u) ^ hash_jenkins32(uint(index.y))) % capacity;
	}

	// the slot of the index's cell, locked and taken for the index if it was free; none if another thread holds the lock
	// or another index the slot
	Optional<uint> try_acquire_cell(int2 index)
	{
		const uint slot = get_slot(index);
		Atomic<uint32_t>* locked = (Atomic<uint32_t>*)&cells[slot].locked;
		if (locked.load() != 0 || locked.compareExchange(0, 1) != 0) return none;
		if (!is_alive(cells[slot]))
		{
			cells[slot].pheromone = Pheromone::None;
			cells[slot].index = index;
			return slot;
		}
		if (all(cells[slot].index == index)) return slot;
		unlock_cell(slot);
		return none;
	}

	void unlock_cell(uint slot)
	{
		Atomic<uint32_t>* locked = (Atomic<uint32_t>*)&cells[slot].locked;
		locked.store(0);
	}

	// the slot of the index's cell, none if it has none
	Optional<uint> get_cell(int2 index)
	{
		const uint slot = get_slot(index);
		if (!is_alive(cells[slot]) || any(cells[slot].index != index)) return none;
		return slot;
	}
}
