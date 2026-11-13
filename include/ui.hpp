#pragma once

#include "app_state.hpp"
#include "vkte/engine.hpp"
#include "vkte_window/ui.hpp"

// the ImGui window that edits the visualizations and shows the timings
class UI
{
public:
	explicit UI(vkte::Engine& engine);
	// records the window into the frame's rendering if it is shown
	void record(vk::CommandBuffer& cb, AppState& app_state);

private:
	vkte::UI& ui;

	void record_window(vk::CommandBuffer& cb, AppState& app_state);
	// runs an ImGui frame without windows while the window is hidden
	void skip_frame();
};
