#pragma once

#include <array>
#include <vector>

#include "app_state.hpp"
#include "shared/push_constants.slang"
#include "simulation.hpp"
#include "ui.hpp"
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
	Simulation simulation;
	UI ui;
	std::array<std::array<vkte::SemaphoreHandle, SEMAPHORE_COUNT>, vkte::frames_in_flight> frame_semaphores;
	std::vector<vkte::SemaphoreHandle> swapchain_semaphores;
	std::array<vkte::DeviceTimerHandle, vkte::frames_in_flight> device_timer_handles;
	std::array<vkte::CommandBufferHandle, vkte::frames_in_flight> cb_handles;
	std::array<Timer, vkte::frames_in_flight> frame_timers;
	std::array<vkte::BufferHandle, vkte::frames_in_flight> uniform_buffer_handles;
	UniformBufferData uniform_buffer_data{};
	// the real time, times the simulation speed, that the simulation hasn't caught up with yet; less than a step
	float unsimulated_time = 0.0f;

	void update_uniform_buffer(AppState& app_state);
	void update_frame_times(AppState& app_state);
	void record_and_present(AppState& app_state);
	void record_simulation(vk::CommandBuffer& cb, const PushConstants& pc, bool reset, uint32_t step_count);
	void record_rendering(vk::CommandBuffer& cb, uint32_t image_idx, AppState& app_state, const PushConstants& pc);
};
