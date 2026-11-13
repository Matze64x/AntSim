#include "ants.hpp"
#include <span>
#include <vector>
#include "util/barrier.hpp"
#include "vkte/buffer.hpp"
#include "vkte/resource_declarations.hpp"

static constexpr vk::ShaderStageFlags render_push_constant_stages = vk::ShaderStageFlagBits::eVertex | vk::ShaderStageFlagBits::eFragment;

Ants::Ants(vkte::Engine& engine, uint32_t ant_count) : engine(engine), ant_count(ant_count)
{}

void Ants::declare_resources(vkte::ResourceDeclarations& declarations, vkte::MemoryManager& memory_manager, const vkte::FrameSettings& frame_settings)
{
	const std::vector<Ant> ants(ant_count);
	vkte::Buffer::Settings ants_settings;
	ants_settings.initial_data = std::as_bytes(std::span(ants));
	ants_settings.element_count = ants.size();
	ants_settings.usage_flags = vk::BufferUsageFlagBits::eStorageBuffer;
	ants_settings.location = vkte::MemoryLocation::DeviceLocal;
	ants_settings.queues = QueueFamilyFlags::Transfer | QueueFamilyFlags::Graphics;
	ants_buffer = memory_manager.add_bindless_buffer("ants_buffer", ants_settings);

	const Nest nest{.pos = glm::vec2(0.0f, 0.0f), .level = 1, .food_amount = 0};
	vkte::Buffer::Settings nest_settings = ants_settings;
	nest_settings.initial_data = std::as_bytes(std::span(&nest, 1));
	nest_settings.element_count = 1;
	nest_buffer = memory_manager.add_bindless_buffer("nest_buffer", nest_settings);

	vkte::Pipeline::ComputeSettings compute_settings;
	compute_settings.push_constant_byte_size = sizeof(PushConstants);
	compute_settings.shader = vkte::Shader("ants.slang", vk::ShaderStageFlagBits::eCompute, "clear");
	clear_pipeline = declarations.add_pipeline(compute_settings);
	compute_settings.shader = vkte::Shader("ants.slang", vk::ShaderStageFlagBits::eCompute, "step_ants");
	step_pipeline = declarations.add_pipeline(compute_settings);
	compute_settings.shader = vkte::Shader("ants.slang", vk::ShaderStageFlagBits::eCompute, "update_hash_grid");
	update_hash_grid_pipeline = declarations.add_pipeline(compute_settings);

	vkte::Pipeline::GraphicsSettings render_settings;
	render_settings.shaders.push_back(vkte::Shader("ants.slang", vk::ShaderStageFlagBits::eVertex, "vertex_main"));
	render_settings.shaders.push_back(vkte::Shader("ants.slang", vk::ShaderStageFlagBits::eFragment, "fragment_main"));
	render_settings.color_formats = {frame_settings.color_format};
	render_settings.depth_format = frame_settings.depth_format;
	render_settings.polygon_mode = vk::PolygonMode::eFill;
	render_settings.primitive_topology = vk::PrimitiveTopology::eTriangleList;
	render_settings.pcrs.push_back(vk::PushConstantRange(render_push_constant_stages, 0, sizeof(PushConstants)));
	render_pipeline = declarations.add_pipeline(render_settings);
}

void Ants::destruct(vkte::MemoryManager& memory_manager)
{
	if (ants_buffer.valid()) memory_manager.destroy(ants_buffer);
	if (nest_buffer.valid()) memory_manager.destroy(nest_buffer);
	ants_buffer = vkte::BufferHandle();
	nest_buffer = vkte::BufferHandle();
}

void Ants::dispatch(vk::CommandBuffer& cb, vkte::PipelineHandle pipeline, const PushConstants& pc)
{
	engine.bind(cb, pipeline);
	cb.pushConstants(engine.get_pipeline_layout(pipeline), vk::ShaderStageFlagBits::eCompute, 0, sizeof(pc), &pc);
	cb.dispatch((ant_count + WORKGROUP_SIZE - 1) / WORKGROUP_SIZE, 1, 1);
}

void Ants::clear(vk::CommandBuffer& cb, const PushConstants& pc)
{
	dispatch(cb, clear_pipeline, pc);
}

void Ants::compute(vk::CommandBuffer& cb, const PushConstants& pc)
{
	dispatch(cb, step_pipeline, pc);
	compute_to_compute_barrier(cb);
	dispatch(cb, update_hash_grid_pipeline, pc);
}

void Ants::draw(vk::CommandBuffer& cb, const PushConstants& pc)
{
	engine.bind(cb, render_pipeline);
	cb.pushConstants(engine.get_pipeline_layout(render_pipeline), render_push_constant_stages, 0, sizeof(pc), &pc);
	cb.draw(6, ant_count, 0, 0);
}
