import shared.nest;

extension Nest
{
	float get_radius()
	{
		return pow(1.2, float(level - 1)) / 100.0 + 0.04;
	}

	// the food at which the nest leaves the given level for the next one, so that a level spans the food from where the
	// previous one ended (from none for the first level) up to where it ends itself
	static uint get_level_food_amount(int level)
	{
		return level > 0 ? 1u << level : 0u;
	}

	// the level of a nest with the food, the one whose span holds it
	static int get_level(uint food_amount)
	{
		return food_amount > 0 ? int(firstbithigh(food_amount)) + 1 : 1;
	}

	// how far the nest got toward its next level, in [0, 1]
	float get_level_progress()
	{
		const float level_start = float(get_level_food_amount(level - 1));
		const float level_end = float(get_level_food_amount(level));
		return saturate((float(food_amount) - level_start) / (level_end - level_start));
	}
}
