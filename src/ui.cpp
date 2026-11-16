#include "ui.hpp"
#include <array>
#include <string>
#include "imgui.h"
#include "map.hpp"
#include "modules/hash_grid.slang"
#include "modules/push_constants.slang"
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

// a colored title over a group of controls, separated from the previous group
static void section(const char* title)
{
	ImGui::Spacing();
	ImGui::Separator();
	ImGui::TextColored(ImVec4(0.0f, 1.0f, 1.0f, 1.0f), "%s", title);
}

void UI::record_window(vk::CommandBuffer& cb, AppState& app_state)
{
	ui.new_frame("AntSim");
	ImGui::PushItemWidth(160.0f);

	ImGui::TextColored(ImVec4(0.0f, 1.0f, 1.0f, 1.0f), "Simulation");
	if (ImGui::Button("Reset Simulation")) app_state.reset_simulation = true;
	ImGui::SliderFloat("Speed", &app_state.simulation_speed, 0.0f, 64.0f, "%.2fx", ImGuiSliderFlags_Logarithmic);
	ImGui::Text("simulated time: %.2f s (%u steps)", float(app_state.simulation_step) * SIMULATION_TIME_STEP, app_state.simulation_step);

	section("Behavior");
	// beyond the trails' reach, ants can't find their way home along them
	ImGui::SliderFloat("Search Distance", &app_state.behavior.search_distance, 1.0f, MAX_TRAIL_DISTANCE, "%.0f m", ImGuiSliderFlags_Logarithmic);
	ImGui::SliderFloat("Explorer Share", &app_state.behavior.explorer_share, 0.0f, 1.0f, "%.2f");

	section("Tools");
	static constexpr std::array<const char*, 3> right_mouse_tools{"Add Food", "Paint Wall", "Erase Wall"};
	int right_mouse_tool = int(app_state.right_mouse_tool);
	if (ImGui::Combo("Right Mouse", &right_mouse_tool, right_mouse_tools.data(), int(right_mouse_tools.size()))) app_state.right_mouse_tool = RightMouseTool(right_mouse_tool);
	// 64 bits, since ImGui's 32-bit sliders end at 2^30 - 1
	static constexpr int64_t min_food_amount = 1;
	static constexpr int64_t max_food_amount = int64_t(1) << int(MAX_FOOD_EXPONENT);
	int64_t food_amount = app_state.food_brush_amount;
	if (ImGui::SliderScalar("Food Amount", ImGuiDataType_S64, &food_amount, &min_food_amount, &max_food_amount, "%lld", ImGuiSliderFlags_Logarithmic)) app_state.food_brush_amount = int32_t(food_amount);
	ImGui::SliderFloat("Wall Brush Radius", &app_state.wall_stroke.radius, 0.02f, 0.5f, "%.2f m");
	if (ImGui::Button("Clear Walls")) app_state.clear_walls = true;

	section("Visualization");
	visualization_controls("Food", app_state.visualizations.food);
	visualization_controls("Food Trail", app_state.visualizations.food_trail);
	visualization_controls("Home Trail", app_state.visualizations.home_trail);
	visualization_controls("Nest", app_state.visualizations.nest);
	visualization_controls("Wall", app_state.visualizations.wall);
	ImGui::ColorEdit3("Ant", &app_state.visualizations.ant_wo_food_color.x);
	ImGui::ColorEdit3("Ant Direction Marker", &app_state.visualizations.ant_wo_food_dir_color.x);
	ImGui::ColorEdit3("Ant With Food", &app_state.visualizations.ant_w_food_color.x);
	ImGui::ColorEdit3("Ant With Food Direction Marker", &app_state.visualizations.ant_w_food_dir_color.x);

	section("Performance");
	ImGui::Text("frame: %.4f ms (%.2f FPS)", app_state.frame_time_ema * 1000, 1.0 / app_state.frame_time_ema);
	ImGui::Text("simulation: %.4f ms", app_state.device_timings[TIMER_SIMULATION]);
	ImGui::Text("rendering: %.4f ms", app_state.device_timings[TIMER_RENDERING]);

	section("Shaders");
	if (ImGui::Button("Reload Shaders")) app_state.reload_shaders = true;
	ImGui::SameLine();
	if (app_state.shaders_compiled) ImGui::TextColored(ImVec4(0.0f, 1.0f, 0.0f, 1.0f), "compiled");
	else ImGui::TextColored(ImVec4(1.0f, 0.0f, 0.0f, 1.0f), "compilation failed");

	ImGui::PopItemWidth();
	ui.end_frame(cb);
}
