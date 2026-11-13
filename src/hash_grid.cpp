#include "hash_grid.hpp"
#include "vkte/buffer.hpp"
#include "vkte/resource_declarations.hpp"

static constexpr vk::ShaderStageFlags render_push_constant_stages = vk::ShaderStageFlagBits::eVertex | vk::ShaderStageFlagBits::eFragment;

HashGrid::HashGrid(vkte::Engine& engine, uint32_t capacity) : engine(engine), capacity(capacity)
{}

void HashGrid::declare_resources(vkte::ResourceDeclarations& declarations, vkte::MemoryManager& memory_manager, const vkte::FrameSettings& frame_settings)
{
	// reset() fills it before the first frame
	vkte::Buffer::Settings buffer_settings;
	buffer_settings.byte_size = sizeof(HashGridCell) * capacity;
	buffer_settings.element_count = capacity;
	buffer_settings.usage_flags = vk::BufferUsageFlagBits::eStorageBuffer;
	buffer_settings.location = vkte::MemoryLocation::DeviceLocal;
	buffer_settings.queues = QueueFamilyFlags::Transfer | QueueFamilyFlags::Graphics;
	hash_grid_buffer = memory_manager.add_bindless_buffer("hash_grid_buffer", buffer_settings);

	vkte::Pipeline::ComputeSettings compute_settings;
	compute_settings.push_constant_byte_size = sizeof(PushConstants);
	compute_settings.shader = vkte::Shader("hash_grid.slang", vk::ShaderStageFlagBits::eCompute, "step_cells");
	step_pipeline = declarations.add_pipeline(compute_settings);

	vkte::Pipeline::GraphicsSettings render_settings;
	render_settings.shaders.push_back(vkte::Shader("hash_grid.slang", vk::ShaderStageFlagBits::eVertex, "vertex_main"));
	render_settings.shaders.push_back(vkte::Shader("hash_grid.slang", vk::ShaderStageFlagBits::eFragment, "fragment_main"));
	render_settings.color_formats = {frame_settings.color_format};
	render_settings.depth_format = frame_settings.depth_format;
	render_settings.polygon_mode = vk::PolygonMode::eFill;
	render_settings.primitive_topology = vk::PrimitiveTopology::eTriangleList;
	render_settings.pcrs.push_back(vk::PushConstantRange(render_push_constant_stages, 0, sizeof(PushConstants)));
	render_pipeline = declarations.add_pipeline(render_settings);
}

void HashGrid::destruct(vkte::MemoryManager& memory_manager)
{
	if (hash_grid_buffer.valid()) memory_manager.destroy(hash_grid_buffer);
	hash_grid_buffer = vkte::BufferHandle();
}

void HashGrid::dispatch(vk::CommandBuffer& cb, vkte::PipelineHandle pipeline, const PushConstants& pc)
{
	engine.bind(cb, pipeline);
	cb.pushConstants(engine.get_pipeline_layout(pipeline), vk::ShaderStageFlagBits::eCompute, 0, sizeof(pc), &pc);
	cb.dispatch((capacity + WORKGROUP_SIZE - 1) / WORKGROUP_SIZE, 1, 1);
}

void HashGrid::reset(vk::CommandBuffer& cb)
{
	cb.fillBuffer(engine.get_memory_manager().get_buffer(hash_grid_buffer).get(), 0, vk::WholeSize, 0);
}

void HashGrid::compute(vk::CommandBuffer& cb, const PushConstants& pc)
{
	dispatch(cb, step_pipeline, pc);
}

void HashGrid::draw(vk::CommandBuffer& cb, const PushConstants& pc)
{
	engine.bind(cb, render_pipeline);
	cb.pushConstants(engine.get_pipeline_layout(render_pipeline), render_push_constant_stages, 0, sizeof(pc), &pc);
	cb.draw(3, 1, 0, 0);
}
