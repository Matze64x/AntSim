#include "work_context.hpp"
#include <algorithm>
#include <span>
#include <string>
#include <utility>
#include "antlog.hpp"
#include "util/barrier.hpp"
#include "vkte/buffer.hpp"
#include "vkte/image.hpp"

WorkContext::WorkContext(vkte::Engine& engine, AppState& app_state)
	: engine(engine), simulation(engine, app_state.ant_count, app_state.hash_grid_capacity), ui(engine)
{
	engine.register_component(simulation);

	vkte::Command& command = engine.get_command();
	vkte::Swapchain& swapchain = engine.get_swapchain();
	app_state.window_extent = glm::ivec2(swapchain.get_extent().width, swapchain.get_extent().height);
	for (uint32_t i = 0; i < vkte::frames_in_flight; ++i)
	{
		for (uint32_t s = 0; s < SEMAPHORE_COUNT; s++) frame_semaphores[i][s] = engine.add_semaphore();
		device_timer_handles[i] = engine.add_device_timer(TIMER_COUNT);
		cb_handles[i] = command.add_command_buffer(QueueFamilyFlags::Graphics);
	}
	swapchain_semaphores.resize(swapchain.get_image_count());
	for (vkte::SemaphoreHandle& semaphore : swapchain_semaphores) semaphore = engine.add_semaphore();
	for (uint32_t i = 0; i < vkte::frames_in_flight; ++i)
	{
		vkte::Buffer::Settings uniform_buffer_settings;
		uniform_buffer_settings.initial_data = std::as_bytes(std::span(&uniform_buffer_data, 1));
		uniform_buffer_settings.element_count = 1;
		uniform_buffer_settings.usage_flags = vk::BufferUsageFlagBits::eUniformBuffer;
		uniform_buffer_settings.location = vkte::MemoryLocation::BARFallbackHostVisible;
		uniform_buffer_settings.queues = QueueFamilyFlags::Graphics;
		uniform_buffer_handles[i] = engine.get_memory_manager().add_bindless_buffer("uniform_buffer_" + std::to_string(i), uniform_buffer_settings);
	}

	vkte::FrameSettings frame_settings;
	frame_settings.color_format = swapchain.get_color_format();
	engine.construct_components(frame_settings);
}

WorkContext::~WorkContext()
{
	for (const vkte::BufferHandle& buffer : uniform_buffer_handles) engine.get_memory_manager().destroy(buffer);
	engine.wait_idle();
	engine.destruct_components();
}

void WorkContext::draw_frame(AppState& app_state)
{
	engine.begin_frame();
	try
	{
		record_and_present(app_state);
	}
	catch (const vk::OutOfDateKHRError&)
	{
		app_state.need_resize = true;
	}
	engine.end_frame();
}

// only for frames that run, so that the simulated time doesn't advance without the simulation
void WorkContext::update_frame_times(AppState& app_state)
{
	const uint32_t current_frame = engine.get_current_frame();
	if (app_state.total_frames > vkte::frames_in_flight)
	{
		for (int i = 0; i < TIMER_COUNT; i++) app_state.device_timings[i] = engine.get(device_timer_handles[current_frame]).get_result(i);
		app_state.frame_time = frame_timers[current_frame].restart() / float(vkte::frames_in_flight);
		const float update_weight = std::clamp(10.0f * app_state.frame_time, 0.0001f, 1.0f);
		app_state.frame_time_ema = app_state.frame_time_ema * (1 - update_weight) + app_state.frame_time * update_weight;
	}
	else frame_timers[current_frame].restart();
	app_state.total_frames++;
}

// The simulation and the rendering go into one command buffer: vkte runs the frames one after another anyway, so a
// separate compute queue wouldn't overlap anything. A frame whose image can't be acquired skips the simulation too, and
// its time.
void WorkContext::record_and_present(AppState& app_state)
{
	vkte::Command& command = engine.get_command();
	vkte::Swapchain& swapchain = engine.get_swapchain();
	const uint32_t current_frame = engine.get_current_frame();
	const vk::Semaphore image_available = engine.get(frame_semaphores[current_frame][S_IMAGE_AVAILABLE]);
	const vk::ResultValue<uint32_t> image_idx = engine.acquire_next_image(image_available);
	if (image_idx.result == vk::Result::eSuboptimalKHR) app_state.need_resize = true;
	else if (image_idx.result != vk::Result::eSuccess) VKTE_THROW("Failed to acquire next image!");
	update_frame_times(app_state);

	// only once the frame is sure to run, so that a skipped frame doesn't lose the reset
	const bool reset = std::exchange(app_state.reset_simulation, false);
	const bool clear_walls = std::exchange(app_state.clear_walls, false);
	if (reset)
	{
		app_state.simulation_step = 0;
		unsimulated_time = 0.0f;
	}
	// the simulation catches up with the real time by whole steps; a slow frame counts as at most 0.1 s, so that the
	// simulation slows down instead of taking ever more steps per frame
	unsimulated_time += std::min(app_state.frame_time, 0.1f) * app_state.simulation_speed;
	const uint32_t step_count = uint32_t(unsimulated_time / SIMULATION_TIME_STEP);
	unsimulated_time -= float(step_count) * SIMULATION_TIME_STEP;

	update_uniform_buffer(app_state);
	const PushConstants pc = simulation.get_push_constants(uniform_buffer_handles[current_frame], app_state.add_food_pos, app_state.add_food_amount, app_state.wall_stroke, app_state.simulation_step);
	vk::CommandBuffer& cb = command.begin(cb_handles[current_frame]);
	record_simulation(cb, pc, reset, clear_walls, step_count);
	app_state.simulation_step += step_count;
	PushConstants render_pc = pc;
	render_pc.step = app_state.simulation_step;
	record_rendering(cb, image_idx.value, app_state, render_pc);
	cb.end();

	const vk::SemaphoreSubmitInfo wait_info(image_available, 0, vk::PipelineStageFlagBits2::eColorAttachmentOutput);
	const vk::Semaphore swapchain_semaphore = engine.get(swapchain_semaphores[image_idx.value]);
	const vk::SemaphoreSubmitInfo signal_info(swapchain_semaphore, 0, vk::PipelineStageFlagBits2::eAllCommands);
	const vk::CommandBufferSubmitInfo cbsi(cb);
	command.submit_graphics(vk::SubmitInfo2({}, wait_info, cbsi, signal_info));

	const vk::PresentInfoKHR present_info(1, &swapchain_semaphore, 1, &swapchain.get(), &image_idx.value);
	const vk::Result result = engine.present(present_info);
	if (result == vk::Result::eSuboptimalKHR) app_state.need_resize = true;
	else if (result != vk::Result::eSuccess) VKTE_THROW("Failed to present!");
}

glm::ivec2 WorkContext::resize(const vkte::PresentSettings& present_settings)
{
	engine.wait_idle();
	engine.resize(present_settings);
	for (const vkte::SemaphoreHandle& semaphore : swapchain_semaphores) engine.destroy(semaphore);
	swapchain_semaphores.resize(engine.get_swapchain().get_image_count());
	for (vkte::SemaphoreHandle& semaphore : swapchain_semaphores) semaphore = engine.add_semaphore();
	const vk::Extent2D swapchain_extent = engine.get_swapchain().get_extent();
	return glm::ivec2(swapchain_extent.width, swapchain_extent.height);
}

bool WorkContext::reload_shaders()
{
	engine.wait_idle();
	return engine.reload_shaders_all();
}

void WorkContext::update_uniform_buffer(AppState& app_state)
{
	uniform_buffer_data.range_min = app_state.view.get_min(app_state.window_size);
	uniform_buffer_data.range_max = app_state.view.get_max(app_state.window_size);
	uniform_buffer_data.visualizations = app_state.visualizations;
	engine.get_memory_manager().get_buffer(uniform_buffer_handles[engine.get_current_frame()]).update_data(uniform_buffer_data);
}

void WorkContext::record_simulation(vk::CommandBuffer& cb, const PushConstants& pc, bool reset, bool clear_walls, uint32_t step_count)
{
	vkte::DeviceTimer& device_timer = engine.get(device_timer_handles[engine.get_current_frame()]);
	if (reset) simulation.reset(cb);
	if (clear_walls) simulation.clear_walls(cb);
	device_timer.reset(cb, TIMER_SIMULATION);
	device_timer.start(cb, TIMER_SIMULATION, vk::PipelineStageFlagBits2::eComputeShader);
	// food also while the simulation is paused
	if (pc.food_amount > 0) simulation.add_food(cb, pc);
	if (pc.wall_stroke.brush != WallBrush::None) simulation.paint_walls(cb, pc);
	PushConstants step_pc = pc;
	for (uint32_t i = 0; i < step_count; i++)
	{
		step_pc.step = pc.step + i;
		simulation.step(cb, step_pc);
	}
	device_timer.stop(cb, TIMER_SIMULATION, vk::PipelineStageFlagBits2::eComputeShader);
	compute_to_graphics_barrier(cb);
}

void WorkContext::record_rendering(vk::CommandBuffer& cb, uint32_t image_idx, AppState& app_state, const PushConstants& pc)
{
	vkte::Swapchain& swapchain = engine.get_swapchain();
	vkte::DeviceTimer& device_timer = engine.get(device_timer_handles[engine.get_current_frame()]);
	device_timer.reset(cb, TIMER_RENDERING);
	device_timer.start(cb, TIMER_RENDERING, vk::PipelineStageFlagBits2::eTopOfPipe);

	const vk::Image color_image = swapchain.get_image(image_idx);
	vkte::perform_image_layout_transition(cb, {
		.image = color_image,
		.range = { .aspect = vk::ImageAspectFlagBits::eColor, .base_mip_level = 0, .level_count = 1, .base_array_layer = 0, .layer_count = 1 },
		.old_layout = vk::ImageLayout::eUndefined,
		.new_layout = vk::ImageLayout::eColorAttachmentOptimal,
		.src_stage = vk::PipelineStageFlagBits2::eColorAttachmentOutput,
		.src_access = vk::AccessFlagBits2::eNone,
		.dst_stage = vk::PipelineStageFlagBits2::eColorAttachmentOutput,
		.dst_access = vk::AccessFlagBits2::eColorAttachmentWrite
	});
	vk::RenderingAttachmentInfo color_att;
	color_att.imageView = swapchain.get_view(image_idx);
	color_att.imageLayout = vk::ImageLayout::eColorAttachmentOptimal;
	color_att.loadOp = vk::AttachmentLoadOp::eClear;
	color_att.storeOp = vk::AttachmentStoreOp::eStore;
	color_att.clearValue.color = vk::ClearColorValue(std::array<float, 4>{0.0f, 0.0f, 0.0f, 1.0f});
	vk::RenderingInfo ri;
	ri.renderArea = vk::Rect2D(vk::Offset2D(0, 0), swapchain.get_extent());
	ri.layerCount = 1;
	ri.colorAttachmentCount = 1;
	ri.pColorAttachments = &color_att;
	cb.beginRendering(ri);

	vk::Viewport viewport;
	viewport.x = 0.0f;
	viewport.y = 0.0f;
	viewport.width = float(swapchain.get_extent().width);
	viewport.height = float(swapchain.get_extent().height);
	viewport.minDepth = 0.0f;
	viewport.maxDepth = 1.0f;
	cb.setViewportWithCount(viewport);
	vk::Rect2D scissor;
	scissor.offset = vk::Offset2D(0, 0);
	scissor.extent = swapchain.get_extent();
	cb.setScissorWithCount(scissor);

	simulation.draw(cb, pc);
	ui.record(cb, app_state);
	cb.endRendering();
	vkte::perform_image_layout_transition(cb, {
		.image = color_image,
		.range = { .aspect = vk::ImageAspectFlagBits::eColor, .base_mip_level = 0, .level_count = 1, .base_array_layer = 0, .layer_count = 1 },
		.old_layout = vk::ImageLayout::eColorAttachmentOptimal,
		.new_layout = vk::ImageLayout::ePresentSrcKHR,
		.src_stage = vk::PipelineStageFlagBits2::eColorAttachmentOutput,
		.src_access = vk::AccessFlagBits2::eColorAttachmentWrite,
		.dst_stage = vk::PipelineStageFlagBits2::eBottomOfPipe,
		.dst_access = vk::AccessFlagBits2::eNone
	});
	device_timer.stop(cb, TIMER_RENDERING, vk::PipelineStageFlagBits2::eBottomOfPipe);
}
