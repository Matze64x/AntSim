#include "simulation.hpp"
#include <string>
#include "shared/ant.slang"
#include "shared/hash_grid.slang"
#include "shared/nest.slang"
#include "util/barrier.hpp"
#include "vkte/buffer.hpp"
#include "vkte/resource_declarations.hpp"

static constexpr vk::ShaderStageFlags render_stages = vk::ShaderStageFlagBits::eVertex | vk::ShaderStageFlagBits::eFragment;

// reset() fills it before the first frame
static vkte::BufferHandle add_buffer(vkte::MemoryManager& memory_manager, const std::string& name, size_t element_size, uint32_t element_count)
{
	vkte::Buffer::Settings settings;
	settings.byte_size = element_size * element_count;
	settings.element_count = element_count;
	settings.usage_flags = vk::BufferUsageFlagBits::eStorageBuffer;
	settings.location = vkte::MemoryLocation::DeviceLocal;
	settings.queues = QueueFamilyFlags::Transfer | QueueFamilyFlags::Graphics;
	return memory_manager.add_bindless_buffer(name, settings);
}

static vkte::PipelineHandle add_compute_pipeline(vkte::ResourceDeclarations& declarations, const std::string& shader, const std::string& entry_point)
{
	vkte::Pipeline::ComputeSettings settings;
	settings.shader = vkte::Shader(shader, vk::ShaderStageFlagBits::eCompute, entry_point);
	settings.push_constant_byte_size = sizeof(PushConstants);
	return declarations.add_pipeline(settings);
}

// of the shader's entry points vertex_main and fragment_main
static vkte::PipelineHandle add_render_pipeline(vkte::ResourceDeclarations& declarations, const vkte::FrameSettings& frame_settings, const std::string& shader)
{
	vkte::Pipeline::GraphicsSettings settings;
	settings.shaders.push_back(vkte::Shader(shader, vk::ShaderStageFlagBits::eVertex, "vertex_main"));
	settings.shaders.push_back(vkte::Shader(shader, vk::ShaderStageFlagBits::eFragment, "fragment_main"));
	settings.color_formats = {frame_settings.color_format};
	settings.pcrs.push_back(vk::PushConstantRange(render_stages, 0, sizeof(PushConstants)));
	return declarations.add_pipeline(settings);
}

Simulation::Simulation(vkte::Engine& engine, uint32_t ant_count, uint32_t hash_grid_capacity) : engine(engine), ant_count(ant_count), hash_grid_capacity(hash_grid_capacity)
{}

void Simulation::declare_resources(vkte::ResourceDeclarations& declarations, vkte::MemoryManager& memory_manager, const vkte::FrameSettings& frame_settings)
{
	ants_buffer = add_buffer(memory_manager, "ants_buffer", sizeof(Ant), ant_count);
	nest_buffer = add_buffer(memory_manager, "nest_buffer", sizeof(Nest), 1);
	hash_grid_buffer = add_buffer(memory_manager, "hash_grid_buffer", sizeof(HashGridCell), hash_grid_capacity);
	add_food_pipeline = add_compute_pipeline(declarations, "hash_grid.slang", "add_food");
	step_ants_pipeline = add_compute_pipeline(declarations, "ants.slang", "step_ants");
	update_hash_grid_pipeline = add_compute_pipeline(declarations, "ants.slang", "update_hash_grid");
	hash_grid_render_pipeline = add_render_pipeline(declarations, frame_settings, "hash_grid.slang");
	ants_render_pipeline = add_render_pipeline(declarations, frame_settings, "ants.slang");
}

void Simulation::destruct(vkte::MemoryManager& memory_manager)
{
	for (vkte::BufferHandle* buffer : {&ants_buffer, &nest_buffer, &hash_grid_buffer})
	{
		if (buffer->valid()) memory_manager.destroy(*buffer);
		*buffer = vkte::BufferHandle();
	}
}

PushConstants Simulation::get_push_constants(vkte::BufferHandle uniform_buffer, glm::vec2 food_pos, int32_t food_amount, uint32_t step) const
{
	PushConstants pc{};
	pc.ants = ants_buffer;
	pc.nest = nest_buffer;
	pc.hash_grid = hash_grid_buffer;
	pc.uniform_buffer = uniform_buffer;
	pc.ant_count = ant_count;
	pc.hash_grid_capacity = hash_grid_capacity;
	pc.food_pos = food_pos;
	pc.food_amount = food_amount;
	pc.step = step;
	return pc;
}

void Simulation::reset(vk::CommandBuffer& cb)
{
	static constexpr Nest initial_nest{.pos = glm::vec2(0.0f, 0.0f), .level = 1, .food_amount = 0};
	vkte::MemoryManager& memory_manager = engine.get_memory_manager();
	cb.fillBuffer(memory_manager.get_buffer(ants_buffer).get(), 0, vk::WholeSize, 0);
	cb.updateBuffer(memory_manager.get_buffer(nest_buffer).get(), 0, sizeof(initial_nest), &initial_nest);
	cb.fillBuffer(memory_manager.get_buffer(hash_grid_buffer).get(), 0, vk::WholeSize, 0);
	transfer_to_compute_barrier(cb);
}

void Simulation::bind(vk::CommandBuffer& cb, vkte::PipelineHandle pipeline, const PushConstants& pc, vk::ShaderStageFlags stages)
{
	engine.bind(cb, pipeline);
	cb.pushConstants(engine.get_pipeline_layout(pipeline), stages, 0, sizeof(pc), &pc);
}

void Simulation::add_food(vk::CommandBuffer& cb, const PushConstants& pc)
{
	bind(cb, add_food_pipeline, pc, vk::ShaderStageFlagBits::eCompute);
	cb.dispatch(1, 1, 1);
	compute_to_compute_barrier(cb);
}

void Simulation::step(vk::CommandBuffer& cb, const PushConstants& pc)
{
	const uint32_t ant_group_count = (ant_count + WORKGROUP_SIZE - 1) / WORKGROUP_SIZE;
	bind(cb, step_ants_pipeline, pc, vk::ShaderStageFlagBits::eCompute);
	cb.dispatch(ant_group_count, 1, 1);
	compute_to_compute_barrier(cb);
	bind(cb, update_hash_grid_pipeline, pc, vk::ShaderStageFlagBits::eCompute);
	cb.dispatch(ant_group_count, 1, 1);
	compute_to_compute_barrier(cb);
}

void Simulation::draw(vk::CommandBuffer& cb, const PushConstants& pc)
{
	// without a depth attachment, later draws cover earlier ones
	bind(cb, hash_grid_render_pipeline, pc, render_stages);
	// a triangle covering the screen
	cb.draw(3, 1, 0, 0);
	bind(cb, ants_render_pipeline, pc, render_stages);
	// a quad per ant
	cb.draw(6, ant_count, 0, 0);
}
