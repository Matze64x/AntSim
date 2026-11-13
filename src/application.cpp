#include "application.hpp"

#include <cmath>
#include "SDL3/SDL_events.h"
#include "glm/common.hpp"
#include "vkte/engine.hpp"
#include "vkte_window/event_handler.hpp"
#include "work_context.hpp"

static void dispatch_pressed_keys(vkte::EventHandler& event_handler, AppState& app_state, vkte::Window& window)
{
	using Key = vkte::Key;
	if (event_handler.was_key_released(Key::G)) app_state.show_ui = !app_state.show_ui;
	if (event_handler.was_key_pressed(Key::F5)) app_state.reload_shaders = true;
	if (event_handler.was_key_pressed(Key::MouseLeft))
	{
		// panning
		const vkte::MouseVector position = event_handler.get_mouse_position();
		app_state.pan_start_pos = glm::vec2(position.x, position.y);
		window.set_relative_mouse_mode(true);
	}
	else if (event_handler.is_key_down(Key::MouseLeft))
	{
		// the view follows the cursor: its motion over the window moves the view by that part of the visible range
		const vkte::MouseVector motion = event_handler.get_mouse_motion();
		const glm::vec2 shift = glm::vec2(motion.x, motion.y) / app_state.window_size * (app_state.visible_range_max - app_state.visible_range_min);
		app_state.visible_range_min -= shift;
		app_state.visible_range_max -= shift;
	}
	if (event_handler.was_key_released(Key::MouseLeft))
	{
		// panning released
		window.set_relative_mouse_mode(false);
		window.warp_mouse(app_state.pan_start_pos.x, app_state.pan_start_pos.y);
	}
	if (event_handler.is_key_down(Key::MouseRight))
	{
		// add food
		const vkte::MouseVector position = event_handler.get_mouse_position();
		glm::vec2 mouse_pos = glm::clamp(glm::vec2(position.x, position.y), glm::vec2(0.0, 0.0), app_state.window_size);
		mouse_pos /= app_state.window_size;
		mouse_pos = mouse_pos * (app_state.visible_range_max - app_state.visible_range_min) + app_state.visible_range_min;
		app_state.add_food_pos = mouse_pos;
		app_state.add_food_amount = 255;
	}
	if (event_handler.was_key_released(Key::MouseRight)) app_state.add_food_amount = 0;
	const float mouse_wheel_motion = event_handler.get_mouse_wheel_motion().y;
	if (std::abs(mouse_wheel_motion) > 0.001f)
	{
		// zoom
		const glm::vec2 center = (app_state.visible_range_min + app_state.visible_range_max) / glm::vec2(2.0f, 2.0f);
		// the length of the displayed range is always the same for both axis
		glm::vec2 centered_range = glm::vec2(app_state.visible_range_min.x, app_state.visible_range_max.x) - glm::vec2(center.x);
		if (mouse_wheel_motion < 0.0f) centered_range *= 1.2;
		else centered_range /= 1.2;
		app_state.visible_range_min = glm::vec2(centered_range.x) + center;
		app_state.visible_range_max = glm::vec2(centered_range.y) + center;
	}
}

int run_application(const ApplicationSettings& settings)
{
	AppState app_state;
	app_state.window_extent = settings.window_resolution;
	app_state.window_size = settings.window_resolution;

	const vkte::PresentSettings present_settings{.mode = vk::PresentModeKHR::eFifo};
	vkte::EngineSettings engine_settings;
	engine_settings.features.khronos_validation = true;
	engine_settings.features.swapchain = true;
	engine_settings.shader_root_dir = settings.shader_dir;
	engine_settings.window_title = "AntSim";
	engine_settings.window_width = app_state.window_extent.x;
	engine_settings.window_height = app_state.window_extent.y;
	engine_settings.present_settings = present_settings;
	vkte::Engine engine(engine_settings);
	WorkContext wc(engine, app_state);
	vkte::EventHandler event_handler;

	bool quit = false;
	SDL_Event e;
	while (!quit)
	{
		event_handler.begin_frame();
		while (SDL_PollEvent(&e))
		{
			quit |= e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED || e.type == SDL_EVENT_QUIT;
			app_state.need_resize |= e.type == SDL_EVENT_WINDOW_RESIZED || e.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED;
			if (e.type == SDL_EVENT_WINDOW_RESIZED) app_state.window_size = glm::vec2(e.window.data1, e.window.data2);
			event_handler.dispatch_event(e);
		}
		dispatch_pressed_keys(event_handler, app_state, engine.get_window());
		if (app_state.reload_shaders)
		{
			app_state.shaders_compiled = wc.reload_shaders();
			app_state.reload_shaders = false;
		}
		wc.draw_frame(app_state);
		if (app_state.need_resize)
		{
			app_state.window_extent = wc.resize(present_settings);
			app_state.need_resize = false;
		}
	}
	return 0;
}
