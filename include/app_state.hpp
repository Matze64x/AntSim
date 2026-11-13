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

struct AppState
{
	Visualizations visualizations;
	glm::vec2 add_food_pos = glm::vec2(0.0f, 0.0f);
	int32_t add_food_amount = 0;
	glm::vec2 visible_range_min = glm::vec2(-5.0f, -5.0f);
	glm::vec2 visible_range_max = glm::vec2(5.0f, 5.0f);
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
	bool shaders_compiled = true;
	// where panning started, in pixels from the window's top left corner, to put the cursor back there
	glm::vec2 pan_start_pos = glm::vec2(0.0f, 0.0f);
};
