// PCG hash white noise
struct Random
{
	uint state;

	__init(uint seed) { state = seed; }

	[mutating] uint next()
	{
		state = state * 747796405u + 2891336453u;
		const uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
		return (word >> 22u) ^ word;
	}

	// in [0, 1]
	[mutating] float next_float()
	{
		return float(next()) / float(uint.maxValue);
	}

	[mutating] float next_float(float min, float max)
	{
		return next_float() * (max - min) + min;
	}

	[mutating] int next_int(int min, int max)
	{
		return int(next_float(float(min), float(max)));
	}

	[mutating] float2 next_float2(float min, float max)
	{
		const float x = next_float(min, max);
		return float2(x, next_float(min, max));
	}
}
