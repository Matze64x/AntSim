#pragma once

#include <filesystem>
#include <optional>
#include <vector>
#include "modules/hash_grid.slang"
#include "modules/nest.slang"

// A cell of food holds at most 2^MAX_FOOD_EXPONENT food. A map's food pixels scale their green value onto the exponent,
// so that dark green is a little food and bright green a lot.
inline constexpr float MAX_FOOD_EXPONENT = 30.0f;

// What the simulation starts from. A map is a PNG with a pixel per hash grid cell, centered on the world's origin (the
// image's x and y axes are the world's): black is wall, green food (green 1 to 255 is 1 to 2^MAX_FOOD_EXPONENT food),
// and blue the nest, which sits at the blue pixels' center. Other colors and transparent pixels are empty ground; pixels
// count as the color whose channel clearly dominates, so that antialiased edges don't turn into something else.
struct Map
{
	// a bit per cell of the world
	std::vector<uint32_t> walls;
	// the hash grid's cells, with the food cells in their slots
	std::vector<HashGridCell> hash_grid;
	Nest nest;
	// food pixels whose slot another food pixel took, which the map loses
	uint32_t dropped_food_cell_count = 0;
};

// the start without a map: no walls, no food, a level 1 nest at the origin
Map get_empty_map(uint32_t hash_grid_capacity);
// none if the file can't be read as an image
std::optional<Map> load_map(const std::filesystem::path& path, uint32_t hash_grid_capacity);
int32_t get_food_amount(uint8_t green);
