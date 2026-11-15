#pragma once
#include <array>
#include <cstdint>
#include "glm/vec2.hpp"
#include "glm/vec3.hpp"
#include "modules/uniform_buffer.slang"
#include "modules/walls.slang"

enum TimerNames {
	TIMER_SIMULATION = 0,
	TIMER_RENDERING = 1,
	TIMER_COUNT
};

inline Visualizations get_default_visualizations()
{
	Visualizations visualizations;
	visualizations.food = Visualization{.color = glm::vec3(0.0f), .color_map = ColorMap::Viridis};
	// dark cyan
	visualizations.food_trail = Visualization{.color = glm::vec3(0.0f, 0.4f, 0.4f), .color_map = ColorMap::CustomColor};
	// dark blue
	visualizations.home_trail = Visualization{.color = glm::vec3(0.0f, 0.0f, 0.4f), .color_map = ColorMap::CustomColor};
	visualizations.nest = Visualization{.color = glm::vec3(0.0f), .color_map = ColorMap::Plasma};
	visualizations.wall = Visualization{.color = glm::vec3(0.45f), .color_map = ColorMap::CustomColor};
	// blue with a pink leading edge
	visualizations.ant_wo_food_color = glm::vec3(0.0f, 0.0f, 1.0f);
	visualizations.ant_wo_food_dir_color = glm::vec3(1.0f, 0.0f, 1.0f);
	// cyan with a pink leading edge
	visualizations.ant_w_food_color = glm::vec3(0.0f, 1.0f, 1.0f);
	visualizations.ant_w_food_dir_color = glm::vec3(1.0f, 0.0f, 1.0f);
	return visualizations;
}

// what the right mouse button does
enum class RightMouseTool : int32_t
{
	AddFood,
	PaintWall,
	EraseWall
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
	Visualizations visualizations = get_default_visualizations();
	glm::vec2 add_food_pos = glm::vec2(0.0f, 0.0f);
	int32_t add_food_amount = 0;
	// the food that the right mouse button puts into a cell
	int32_t food_brush_amount = 1000;
	RightMouseTool right_mouse_tool = RightMouseTool::AddFood;
	// what the right mouse button painted or erased of the walls since the last frame
	WallStroke wall_stroke{.from = glm::vec2(0.0f), .to = glm::vec2(0.0f), .radius = 0.06f, .brush = WallBrush::None};
	View view;
	const uint32_t ant_count = 1'00;
	const uint32_t hash_grid_capacity = 100'000;
	uint32_t total_frames = 0;
	std::array<float, TIMER_COUNT> device_timings{};
	// the time a frame took
	float frame_time = 1.0f / 60.0f;
	float frame_time_ema = 1.0f / 60.0f;
	// simulated seconds per real second; 0 pauses the simulation
	float simulation_speed = 1.0f;
	// the simulation steps done since the start or the last reset
	uint32_t simulation_step = 0;
	// in pixels, the swapchain's
	glm::ivec2 window_extent = glm::ivec2(1000, 1000);
	// in window coordinates, which mouse positions are in and which differ from pixels on scaled displays
	glm::vec2 window_size = glm::vec2(1000.0f, 1000.0f);
	bool show_ui = true;
	bool need_resize = false;
	bool reload_shaders = false;
	// fills the buffers with the simulation's start in the next frame, which the first frame does too
	bool reset_simulation = true;
	// removes all walls in the next frame, which the first frame does too; resetting the simulation keeps them
	bool clear_walls = true;
	bool shaders_compiled = true;
	// while panning, the world position that stays under the cursor
	glm::vec2 pan_anchor = glm::vec2(0.0f, 0.0f);
};
