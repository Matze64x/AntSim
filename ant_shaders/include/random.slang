// PCG hash white noise

uint pcg_hash(uint seed)
{
	const uint state = seed * 747796405u + 2891336453u;
	const uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

// in [0, 1), from the top 24 bits of the hash, which a float represents exactly
float hash_to_unit_float(uint hash)
{
	return float(hash >> 8u) * 5.9604644775390625e-8f;
}

// maps rnd in [0, 1) to [lower_bound, upper_bound); scaling can round up to upper_bound, which becomes the float below it
float scale_to_range(float rnd, float lower_bound, float upper_bound)
{
	const float value = rnd * (upper_bound - lower_bound) + lower_bound;
	if (value < upper_bound || upper_bound <= lower_bound) return value;
	if (upper_bound == 0.0f) return -asfloat(1u);
	const uint bits = asuint(upper_bound);
	return asfloat(upper_bound > 0.0f ? bits - 1u : bits + 1u);
}

// in [lower_bound, upper_bound]; a range of 0 is the full range of 2^32 values
int hash_to_range(uint hash, int lower_bound, int upper_bound)
{
	const uint range = uint(upper_bound) - uint(lower_bound) + 1u;
	return int((range == 0u ? hash : hash % range) + uint(lower_bound));
}

struct Random
{
	uint state;

	__init(uint seed) { state = seed; }

	[mutating] uint next_hash()
	{
		const uint hash = pcg_hash(state);
		state = state * 747796405u + 2891336453u;
		return hash;
	}

	// in [0, 1)
	[mutating] float get_float() { return hash_to_unit_float(next_hash()); }
	// in [lower_bound, upper_bound)
	[mutating] float get_float(float lower_bound, float upper_bound) { return scale_to_range(get_float(), lower_bound, upper_bound); }
	// in [lower_bound, upper_bound]
	[mutating] int get_int(int lower_bound, int upper_bound) { return hash_to_range(next_hash(), lower_bound, upper_bound); }

	// both components in [lower_bound, upper_bound)
	[mutating] float2 get_float2(float lower_bound, float upper_bound)
	{
		const float x = get_float(lower_bound, upper_bound);
		return float2(x, get_float(lower_bound, upper_bound));
	}

	// uniformly distributed in the disk of radius 1 around the origin
	[mutating] float2 get_float2_in_disk()
	{
		const float radius = sqrt(get_float());
		const float angle = get_float(0.0f, 2.0f * float.getPi());
		return radius * float2(cos(angle), sin(angle));
	}
}

// in [0, 1)
float random_float(uint seed) { return hash_to_unit_float(pcg_hash(seed)); }
// in [lower_bound, upper_bound)
float random_float(uint seed, float lower_bound, float upper_bound) { return scale_to_range(random_float(seed), lower_bound, upper_bound); }
// in [lower_bound, upper_bound]
int random_int(uint seed, int lower_bound, int upper_bound) { return hash_to_range(pcg_hash(seed), lower_bound, upper_bound); }
