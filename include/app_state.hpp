#pragma once
#include <array>
#include <cstdint>
#include "glm/vec2.hpp"
#include "glm/vec3.hpp"
#include "shared/uniform_buffer.slang"

enum TimerNames {
	TIMER_RENDERING_ALL = 0,
	TIMER_ANTS_STEP = 1,
	TIMER_HASH_GRID_STEP = 2,
	TIMER_COUNT
};

// what the UI edits of how the simulation is shown
struct Visualizations
{
	Visualization food{.color = glm::vec3(0.0f), .color_map = ColorMap::Viridis};
	// in dark yellow
	Visualization food_pheromone{.color = glm::vec3(0.0f, 0.4f, 0.4f), .color_map = ColorMap::CustomColor};
	Visualization nest{.color = glm::vec3(0.0f), .color_map = ColorMap::Plasma};
	// in dark blue
	Visualization nest_pheromone{.color = glm::vec3(0.0f, 0.0f, 0.4f), .color_map = ColorMap::CustomColor};
	// blue
	glm::vec3 ant_wo_food_color = glm::vec3(0.0f, 0.0f, 1.0f);
	// the leading edge in pink
	glm::vec3 ant_wo_food_dir_color = glm::vec3(1.0f, 0.0f, 1.0f);
	// yellow
	glm::vec3 ant_w_food_color = glm::vec3(0.0f, 1.0f, 1.0f);
	// the leading edge in pink
	glm::vec3 ant_w_food_dir_color = glm::vec3(1.0f, 0.0f, 1.0f);
};

// The part of the world the window shows: as tall as height and as wide as the window's aspect ratio makes it, so that a
// world unit is as long along both axes on the screen.
struct View
{
	glm::vec2 center = glm::vec2(0.0f, 0.0f);
	float height = 10.0f;

	glm::vec2 get_extent(glm::vec2 window_size) const { return glm::vec2(height * window_size.x / window_size.y, height); }
	glm::vec2 get_min(glm::vec2 window_size) const { return center - get_extent(window_size) / 2.0f; }
	glm::vec2 get_max(glm::vec2 window_size) const { return center + get_extent(window_size) / 2.0f; }
	// the world position at a point in the window, in window coordinates from its top left corner
	glm::vec2 to_world(glm::vec2 window_point, glm::vec2 window_size) const { return get_min(window_size) + window_point / window_size * get_extent(window_size); }
};

struct AppState
{
	Visualizations visualizations;
	glm::vec2 add_food_pos = glm::vec2(0.0f, 0.0f);
	int32_t add_food_amount = 0;
	View view;
	const uint32_t ant_count = 1'00;
	const uint32_t hash_grid_capacity = 100'000;
	uint32_t total_frames = 0;
	std::array<float, TIMER_COUNT> device_timings{};
	// the time a frame took
	float frame_time = 1.0f / 60.0f;
	// what the simulation advances by per frame, so that a slow frame doesn't make the ants jump
	float capped_frame_time = 1.0f / 60.0f;
	float frame_time_ema = 1.0f / 60.0f;
	// the simulated time, the sum of the capped frame times
	float total_time = 1.0f / 60.0f;
	// in pixels, the swapchain's
	glm::ivec2 window_extent = glm::ivec2(1000, 1000);
	// in window coordinates, which mouse positions are in and which differ from pixels on scaled displays
	glm::vec2 window_size = glm::vec2(1000.0f, 1000.0f);
	bool show_ui = true;
	bool need_resize = false;
	bool reload_shaders = false;
	// fills the buffers with the simulation's start in the next frame, which the first frame does too
	bool reset_simulation = true;
	bool shaders_compiled = true;
	// while panning, the world position that stays under the cursor
	glm::vec2 pan_anchor = glm::vec2(0.0f, 0.0f);
};
