import include.random;

// The steps of a given length that passed during the frame, shifted for each ant to decorrelate the ants' behavior, so
// that what happens per step doesn't depend on the frame rate.
struct AntTime
{
	float total_time_shifted;
	float frame_time;

	__init(float total_time, float frame_time, uint ant_index, uint ant_count, float shift_scale)
	{
		total_time_shifted = total_time + float(ant_index) / (shift_scale * float(ant_count));
		this.frame_time = frame_time;
	}

	bool step_passed(float step_length)
	{
		const uint prev_steps_passed = uint((total_time_shifted - frame_time) / step_length);
		const uint steps_passed = uint(total_time_shifted / step_length);
		return steps_passed != prev_steps_passed;
	}

	// whether a step passed and, with the probability, something happens in it
	bool chance(inout Random rng, float step_length, float probability)
	{
		return step_passed(step_length) && rng.next_float() < probability;
	}
}
