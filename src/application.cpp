#include "application.hpp"

#include <cmath>

#include "SDL3/SDL_events.h"
#include "glm/common.hpp"
#include "vkte/engine.hpp"
#include "vkte_window/event_handler.hpp"
#include "work_context.hpp"

static void dispatch_pressed_keys(vkte::EventHandler& event_handler, AppState& app_state)
{
	using Key = vkte::Key;
	if (event_handler.was_key_released(Key::G)) app_state.show_ui = !app_state.show_ui;
	if (event_handler.was_key_pressed(Key::F5)) app_state.reload_shaders = true;
	const vkte::MouseVector position = event_handler.get_mouse_position();
	const glm::vec2 mouse_world_pos = app_state.view.to_world(glm::vec2(position.x, position.y), app_state.window_size);
	// panning drags the world: the point under the cursor when the button went down stays under it
	if (event_handler.was_key_pressed(Key::MouseLeft)) app_state.pan_anchor = mouse_world_pos;
	else if (event_handler.is_key_down(Key::MouseLeft)) app_state.view.center += app_state.pan_anchor - mouse_world_pos;
	if (event_handler.is_key_down(Key::MouseRight))
	{
		const glm::vec2 cursor_world_pos = app_state.view.to_world(glm::clamp(glm::vec2(position.x, position.y), glm::vec2(0.0f), app_state.window_size), app_state.window_size);
		if (app_state.right_mouse_tool == RightMouseTool::AddFood)
		{
			app_state.add_food_pos = cursor_world_pos;
			app_state.add_food_amount = 255;
		}
		else
		{
			// from where the cursor was in the last frame, so that fast strokes leave no gaps
			WallStroke& stroke = app_state.wall_stroke;
			stroke.from = event_handler.was_key_pressed(Key::MouseRight) ? cursor_world_pos : stroke.to;
			stroke.to = cursor_world_pos;
			stroke.brush = app_state.right_mouse_tool == RightMouseTool::PaintWall ? WallBrush::Paint : WallBrush::Erase;
		}
	}
	if (event_handler.was_key_released(Key::MouseRight))
	{
		app_state.add_food_amount = 0;
		app_state.wall_stroke.brush = WallBrush::None;
	}
	const float mouse_wheel_motion = event_handler.get_mouse_wheel_motion().y;
	// zoom about the cursor: the point under it stays under it
	if (std::abs(mouse_wheel_motion) > 0.001f)
	{
		const float scale = mouse_wheel_motion < 0.0f ? 1.2f : 1.0f / 1.2f;
		app_state.view.height *= scale;
		app_state.view.center = mouse_world_pos - (mouse_world_pos - app_state.view.center) * scale;
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
		dispatch_pressed_keys(event_handler, app_state);
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
