#include "ui.hpp"
#include <array>
#include <string>
#include "imgui.h"
#include "shared/push_constants.slang"
#include "backends/imgui_impl_sdl3.h"

UI::UI(vkte::Engine& engine) : ui(engine.get_ui())
{}

void UI::record(vk::CommandBuffer& cb, AppState& app_state)
{
	if (app_state.show_ui) record_window(cb, app_state);
	else skip_frame();
}

// Runs an ImGui frame without windows, so that ImGui still takes the input it queued and no longer claims the mouse or
// the keyboard, which vkte::EventHandler would otherwise keep ignoring while the UI is hidden.
void UI::skip_frame()
{
	ImGui_ImplSDL3_NewFrame();
	ImGui::NewFrame();
	ImGui::EndFrame();
}

// the color map to show a quantity with, and the color if it is a custom one
static void visualization_controls(const char* name, Visualization& visualization)
{
	static constexpr std::array<const char*, 6> color_maps{"None", "viridis", "plasma", "magma", "inferno", "custom color"};
	int color_map = int(visualization.color_map);
	if (ImGui::Combo(name, &color_map, color_maps.data(), int(color_maps.size()))) visualization.color_map = ColorMap(color_map);
	if (visualization.color_map == ColorMap::CustomColor) ImGui::ColorEdit3((std::string(name) + " Color").c_str(), &visualization.color.x);
}

void UI::record_window(vk::CommandBuffer& cb, AppState& app_state)
{
	ui.new_frame("AntSim");
	ImGui::PushItemWidth(80.0f);
	if (ImGui::Button("Reset Simulation")) app_state.reset_simulation = true;
	ImGui::SameLine();
	if (ImGui::Button("Reload Shaders")) app_state.reload_shaders = true;
	ImGui::SameLine();
	if (ImGui::Button("Clear Walls")) app_state.clear_walls = true;
	if (app_state.shaders_compiled) ImGui::TextColored(ImVec4(0.0f, 1.0f, 0.0f, 1.0f), "Shaders compiled");
	else ImGui::TextColored(ImVec4(1.0f, 0.0f, 0.0f, 1.0f), "Shader compilation failed");

	ImGui::PushItemWidth(200.0f);
	ImGui::TextColored(ImVec4(0.0f, 1.0f, 1.0f, 1.0f), "Visualization");
	visualization_controls("Food", app_state.visualizations.food);
	visualization_controls("Food Trail", app_state.visualizations.food_trail);
	visualization_controls("Nest", app_state.visualizations.nest);
	visualization_controls("Wall", app_state.visualizations.wall);
	ImGui::Text("Ants Colors");
	ImGui::ColorEdit3("Without Food", &app_state.visualizations.ant_wo_food_color.x);
	ImGui::ColorEdit3("Without Food Direction Marker", &app_state.visualizations.ant_wo_food_dir_color.x);
	ImGui::ColorEdit3("With Food", &app_state.visualizations.ant_w_food_color.x);
	ImGui::ColorEdit3("With Food Direction Marker", &app_state.visualizations.ant_w_food_dir_color.x);
	ImGui::PopItemWidth();
	ImGui::Separator();

	static constexpr std::array<const char*, 3> right_mouse_tools{"Add Food", "Paint Wall", "Erase Wall"};
	int right_mouse_tool = int(app_state.right_mouse_tool);
	ImGui::PushItemWidth(120.0f);
	if (ImGui::Combo("Right Mouse", &right_mouse_tool, right_mouse_tools.data(), int(right_mouse_tools.size()))) app_state.right_mouse_tool = RightMouseTool(right_mouse_tool);
	ImGui::SliderFloat("Wall Brush Radius", &app_state.wall_stroke.radius, 0.02f, 0.5f, "%.2f m");
	ImGui::PopItemWidth();
	ImGui::Separator();

	ImGui::Text("%.4f ms; FPS: %.2f", app_state.frame_time_ema * 1000, 1.0 / app_state.frame_time_ema);
	ImGui::SliderFloat("Speed", &app_state.simulation_speed, 0.0f, 8.0f, "%.2fx");
	ImGui::Text("simulated time: %.2f s (%u steps)", float(app_state.simulation_step) * SIMULATION_TIME_STEP, app_state.simulation_step);
	ImGui::Text("simulation: %.4f ms", app_state.device_timings[TIMER_SIMULATION]);
	ImGui::Text("rendering: %.4f ms", app_state.device_timings[TIMER_RENDERING]);
	ImGui::PopItemWidth();
	ui.end_frame(cb);
}
