import include.random;
import shared.push_constants;

// Whether intervals of a given length ended during a simulation step, so that how often something happens doesn't depend
// on the step length. The time is shifted for each ant to decorrelate the ants' behavior.
struct AntTime
{
	float shifted_time;

	__init(float time, uint ant_index, uint ant_count, float shift_scale)
	{
		shifted_time = time + float(ant_index) / (shift_scale * float(ant_count));
	}

	bool interval_passed(float interval_length)
	{
		const uint prev_intervals_passed = uint((shifted_time - SIMULATION_TIME_STEP) / interval_length);
		const uint intervals_passed = uint(shifted_time / interval_length);
		return intervals_passed != prev_intervals_passed;
	}

	// whether an interval passed and, with the probability, something happens in it
	bool chance(inout Random rng, float interval_length, float probability)
	{
		return interval_passed(interval_length) && rng.get_float() < probability;
	}
}
