#pragma once

#include <array>
#include <vector>

#include "ants.hpp"
#include "app_state.hpp"
#include "hash_grid.hpp"
#include "shared/push_constants.slang"
#include "shared/uniform_buffer.slang"
#include "util/timer.hpp"
#include "glm/vec2.hpp"
#include "vkte/engine.hpp"

enum SemaphoreNames
{
	S_IMAGE_AVAILABLE = 0,
	SEMAPHORE_COUNT
};

// records each frame's simulation and rendering
class WorkContext
{
public:
	WorkContext(vkte::Engine& engine, AppState& app_state);
	~WorkContext();
	void draw_frame(AppState& app_state);
	glm::ivec2 resize(const vkte::PresentSettings& present_settings);
	// recompiles every shader; returns false, keeping the old ones, if any failed to compile
	bool reload_shaders();

private:
	vkte::Engine& engine;
	Ants ants;
	HashGrid hash_grid;
	vkte::UI& ui;
	std::array<std::array<vkte::SemaphoreHandle, SEMAPHORE_COUNT>, vkte::frames_in_flight> frame_semaphores;
	std::vector<vkte::SemaphoreHandle> swapchain_semaphores;
	std::array<vkte::DeviceTimerHandle, vkte::frames_in_flight> device_timer_handles;
	std::array<vkte::CommandBufferHandle, vkte::frames_in_flight> cb_handles;
	std::array<Timer, vkte::frames_in_flight> frame_timers;
	std::array<vkte::BufferHandle, vkte::frames_in_flight> uniform_buffer_handles;
	UniformBufferData uniform_buffer_data{};

	void update_uniform_buffer(AppState& app_state);
	PushConstants get_push_constants(const AppState& app_state) const;
	void update_frame_times(AppState& app_state);
	void record_and_present(AppState& app_state);
	void record_simulation(vk::CommandBuffer& cb, const PushConstants& pc, bool reset);
	void record_rendering(vk::CommandBuffer& cb, uint32_t image_idx, AppState& app_state, const PushConstants& pc);
	void render_ui(vk::CommandBuffer& cb, AppState& app_state);
};
