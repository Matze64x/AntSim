#include "map.hpp"
#include <algorithm>
#include <cmath>
#include "antlog.hpp"
#include "modules/walls.slang"
#include "stb/stb_image.h"

enum class PixelKind
{
	Ground,
	Wall,
	Food,
	Nest
};

// a channel clearly dominates if it is more than twice the others
static PixelKind get_pixel_kind(const uint8_t* pixel)
{
	const uint8_t r = pixel[0];
	const uint8_t g = pixel[1];
	const uint8_t b = pixel[2];
	if (pixel[3] < 128) return PixelKind::Ground;
	if (g > 2 * std::max(r, b)) return PixelKind::Food;
	if (b > 2 * std::max(r, g)) return PixelKind::Nest;
	if (int(r) + int(g) + int(b) < 3 * 128) return PixelKind::Wall;
	return PixelKind::Ground;
}

int32_t get_food_amount(uint8_t green)
{
	if (green == 0) return 0;
	return int32_t(std::lround(std::exp2(MAX_FOOD_EXPONENT * float(green - 1) / 254.0f)));
}

Map get_empty_map(uint32_t hash_grid_capacity)
{
	Map map;
	map.walls.resize(WALL_WORD_COUNT, 0);
	map.hash_grid.resize(hash_grid_capacity, HashGridCell{});
	map.nest = Nest{.pos = glm::vec2(0.0f), .level = 1, .food_amount = 0};
	return map;
}

std::optional<Map> load_map(const std::filesystem::path& path, uint32_t hash_grid_capacity)
{
	int width = 0;
	int height = 0;
	int channel_count = 0;
	stbi_uc* pixels = stbi_load(path.string().c_str(), &width, &height, &channel_count, 4);
	if (!pixels)
	{
		antlog::error("Failed to load the map {}: {}", path.string(), stbi_failure_reason());
		return std::nullopt;
	}
	Map map = get_empty_map(hash_grid_capacity);
	glm::vec2 nest_pos_sum(0.0f);
	uint32_t nest_pixel_count = 0;
	uint32_t outside_pixel_count = 0;
	for (int y = 0; y < height; y++)
	{
		for (int x = 0; x < width; x++)
		{
			const uint8_t* pixel = pixels + 4 * (size_t(y) * size_t(width) + size_t(x));
			const PixelKind kind = get_pixel_kind(pixel);
			if (kind == PixelKind::Ground) continue;
			const int2 index(x - width / 2, y - height / 2);
			if (!is_in_world(index))
			{
				outside_pixel_count++;
				continue;
			}
			if (kind == PixelKind::Wall)
			{
				const uint32_t bit = get_wall_bit(index);
				map.walls[bit / 32] |= 1u << (bit % 32);
			}
			else if (kind == PixelKind::Nest)
			{
				nest_pos_sum += (glm::vec2(index) + 0.5f) * HASH_GRID_CELL_LENGTH;
				nest_pixel_count++;
			}
			else
			{
				HashGridCell& cell = map.hash_grid[get_hash_grid_slot(index, hash_grid_capacity)];
				if (cell.food_amount > 0)
				{
					map.dropped_food_cell_count++;
					continue;
				}
				cell.key = get_hash_grid_key(index);
				cell.food_amount = get_food_amount(pixel[1]);
			}
		}
	}
	stbi_image_free(pixels);
	if (nest_pixel_count > 0) map.nest.pos = nest_pos_sum / float(nest_pixel_count);
	if (outside_pixel_count > 0) antlog::warn("The map {} reaches beyond the world; {} of its pixels are lost", path.string(), outside_pixel_count);
	if (map.dropped_food_cell_count > 0) antlog::warn("The map {} has more food pixels than the hash grid has room for; {} of them are lost", path.string(), map.dropped_food_cell_count);
	return map;
}
