#include "work_context.hpp"
#include <algorithm>
#include <span>
#include <string>
#include "antlog.hpp"
#include "imgui.h"
#include "backends/imgui_impl_sdl3.h"
#include "util/barrier.hpp"
#include "vkte/buffer.hpp"
#include "vkte/image.hpp"

WorkContext::WorkContext(vkte::Engine& engine, AppState& app_state)
	: engine(engine), ants(engine, app_state.ant_count), hash_grid(engine, app_state.hash_grid_capacity), ui(engine.get_ui())
{
	engine.register_component(ants);
	engine.register_component(hash_grid);

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
	frame_settings.depth_format = swapchain.get_depth_format();
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
		app_state.capped_frame_time = std::min(app_state.frame_time, 0.1f);
		app_state.total_time += app_state.capped_frame_time;
		const float update_weight = std::clamp(10.0f * app_state.capped_frame_time, 0.0001f, 1.0f);
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

	update_uniform_buffer(app_state);
	const PushConstants pc = get_push_constants(app_state);
	vk::CommandBuffer& cb = command.begin(cb_handles[current_frame]);
	record_simulation(cb, pc);
	record_rendering(cb, image_idx.value, app_state, pc);
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
	const Visualizations& visualizations = app_state.visualizations;
	uniform_buffer_data.food = visualizations.food;
	uniform_buffer_data.food_pheromone = visualizations.food_pheromone;
	uniform_buffer_data.nest = visualizations.nest;
	uniform_buffer_data.nest_pheromone = visualizations.nest_pheromone;
	uniform_buffer_data.ant_wo_food_color = visualizations.ant_wo_food_color;
	uniform_buffer_data.ant_wo_food_dir_color = visualizations.ant_wo_food_dir_color;
	uniform_buffer_data.ant_w_food_color = visualizations.ant_w_food_color;
	uniform_buffer_data.ant_w_food_dir_color = visualizations.ant_w_food_dir_color;
	uniform_buffer_data.frame_idx = app_state.total_frames;
	uniform_buffer_data.frame_time = app_state.capped_frame_time;
	uniform_buffer_data.total_time = app_state.total_time;
	engine.get_memory_manager().get_buffer(uniform_buffer_handles[engine.get_current_frame()]).update_data(uniform_buffer_data);
}

PushConstants WorkContext::get_push_constants(const AppState& app_state) const
{
	PushConstants pc{};
	pc.ants = ants.get_ants_buffer();
	pc.nest = ants.get_nest_buffer();
	pc.hash_grid = hash_grid.get_buffer();
	pc.uniform_buffer = uniform_buffer_handles[engine.get_current_frame()];
	pc.ant_count = app_state.ant_count;
	pc.hash_grid_capacity = app_state.hash_grid_capacity;
	pc.food_pos = app_state.add_food_pos;
	pc.food_amount = app_state.add_food_amount;
	return pc;
}

void WorkContext::record_simulation(vk::CommandBuffer& cb, const PushConstants& pc)
{
	vkte::DeviceTimer& device_timer = engine.get(device_timer_handles[engine.get_current_frame()]);
	if (!cleared)
	{
		ants.clear(cb, pc);
		hash_grid.clear(cb, pc);
		compute_to_compute_barrier(cb);
		cleared = true;
	}
	device_timer.reset(cb, TIMER_ANTS_STEP);
	device_timer.reset(cb, TIMER_HASH_GRID_STEP);
	device_timer.start(cb, TIMER_ANTS_STEP, vk::PipelineStageFlagBits2::eComputeShader);
	ants.compute(cb, pc);
	device_timer.stop(cb, TIMER_ANTS_STEP, vk::PipelineStageFlagBits2::eComputeShader);
	compute_to_compute_barrier(cb);
	device_timer.start(cb, TIMER_HASH_GRID_STEP, vk::PipelineStageFlagBits2::eComputeShader);
	hash_grid.compute(cb, pc);
	device_timer.stop(cb, TIMER_HASH_GRID_STEP, vk::PipelineStageFlagBits2::eComputeShader);
	compute_to_graphics_barrier(cb);
}

// Runs an ImGui frame without windows, so that ImGui still takes the input it queued and no longer claims the mouse or
// the keyboard, which vkte::EventHandler would otherwise keep ignoring while the UI is hidden.
static void skip_ui()
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

void WorkContext::render_ui(vk::CommandBuffer& cb, AppState& app_state)
{
	ui.new_frame("AntSim");
	ImGui::PushItemWidth(80.0f);
	if (ImGui::Button("Reload Shaders")) app_state.reload_shaders = true;
	if (app_state.shaders_compiled) ImGui::TextColored(ImVec4(0.0f, 1.0f, 0.0f, 1.0f), "Shaders compiled");
	else ImGui::TextColored(ImVec4(1.0f, 0.0f, 0.0f, 1.0f), "Shader compilation failed");

	ImGui::PushItemWidth(200.0f);
	ImGui::TextColored(ImVec4(0.0f, 1.0f, 1.0f, 1.0f), "Visualization");
	visualization_controls("Food", app_state.visualizations.food);
	visualization_controls("Food Pheromone", app_state.visualizations.food_pheromone);
	visualization_controls("Nest", app_state.visualizations.nest);
	visualization_controls("Nest Pheromone", app_state.visualizations.nest_pheromone);
	ImGui::Text("Ants Colors");
	ImGui::ColorEdit3("Without Food", &app_state.visualizations.ant_wo_food_color.x);
	ImGui::ColorEdit3("Without Food Direction Marker", &app_state.visualizations.ant_wo_food_dir_color.x);
	ImGui::ColorEdit3("With Food", &app_state.visualizations.ant_w_food_color.x);
	ImGui::ColorEdit3("With Food Direction Marker", &app_state.visualizations.ant_w_food_dir_color.x);
	ImGui::PopItemWidth();
	ImGui::Separator();

	ImGui::Text("%.4f ms; FPS: %.2f", app_state.frame_time_ema * 1000, 1.0 / app_state.frame_time_ema);
	ImGui::Text("total time: %.4f s", app_state.total_time);
	ImGui::Text("RENDERING_ALL: %.4f ms", app_state.device_timings[TIMER_RENDERING_ALL]);
	ImGui::Text("ANTS_STEP: %.4f ms", app_state.device_timings[TIMER_ANTS_STEP]);
	ImGui::Text("HASH_GRID_STEP: %.4f ms", app_state.device_timings[TIMER_HASH_GRID_STEP]);
	ImGui::PopItemWidth();
	ui.end_frame(cb);
}

void WorkContext::record_rendering(vk::CommandBuffer& cb, uint32_t image_idx, AppState& app_state, const PushConstants& pc)
{
	vkte::Swapchain& swapchain = engine.get_swapchain();
	vkte::DeviceTimer& device_timer = engine.get(device_timer_handles[engine.get_current_frame()]);
	device_timer.reset(cb, TIMER_RENDERING_ALL);
	device_timer.start(cb, TIMER_RENDERING_ALL, vk::PipelineStageFlagBits2::eTopOfPipe);

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
	vk::RenderingAttachmentInfo depth_att;
	depth_att.imageView = swapchain.get_depth_view();
	depth_att.imageLayout = vk::ImageLayout::eDepthStencilAttachmentOptimal;
	depth_att.loadOp = vk::AttachmentLoadOp::eClear;
	depth_att.storeOp = vk::AttachmentStoreOp::eDontCare;
	depth_att.clearValue.depthStencil = vk::ClearDepthStencilValue(1.0f, 0);
	vk::RenderingInfo ri;
	ri.renderArea = vk::Rect2D(vk::Offset2D(0, 0), swapchain.get_extent());
	ri.layerCount = 1;
	ri.colorAttachmentCount = 1;
	ri.pColorAttachments = &color_att;
	ri.pDepthAttachment = &depth_att;
	ri.pStencilAttachment = (vkte::default_aspect_for_format(swapchain.get_depth_format()) & vk::ImageAspectFlagBits::eStencil) ? &depth_att : nullptr;
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

	// the ants first, so that the hash grid, at the same depth, fills only what they leave
	ants.draw(cb, pc);
	hash_grid.draw(cb, pc);
	if (app_state.show_ui) render_ui(cb, app_state);
	else skip_ui();
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
	device_timer.stop(cb, TIMER_RENDERING_ALL, vk::PipelineStageFlagBits2::eBottomOfPipe);
}
