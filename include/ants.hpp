#pragma once

#include "shared/ant.slang"
#include "shared/nest.slang"
#include "shared/push_constants.slang"
#include "vkte/component.hpp"
#include "vkte/engine.hpp"
#include "vkte/resource_handles.hpp"

// the ants and their nest
class Ants : public vkte::Component
{
public:
	Ants(vkte::Engine& engine, uint32_t ant_count);
	const char* name() const override { return "ants"; }
	void declare_resources(vkte::ResourceDeclarations& declarations, vkte::MemoryManager& memory_manager, const vkte::FrameSettings& frame_settings) override;
	void destruct(vkte::MemoryManager& memory_manager) override;
	// records filling the buffers with the simulation's start: no ants yet (they start at the nest) and a level 1 nest
	void reset(vk::CommandBuffer& cb);
	// moves the ants, then lets them mark and take food from the hash grid's cells
	void compute(vk::CommandBuffer& cb, const PushConstants& pc);
	void draw(vk::CommandBuffer& cb, const PushConstants& pc);
	vkte::BufferHandle get_ants_buffer() const { return ants_buffer; }
	vkte::BufferHandle get_nest_buffer() const { return nest_buffer; }

private:
	vkte::Engine& engine;
	uint32_t ant_count;
	vkte::BufferHandle ants_buffer;
	vkte::BufferHandle nest_buffer;
	vkte::PipelineHandle render_pipeline;
	vkte::PipelineHandle step_pipeline;
	vkte::PipelineHandle update_hash_grid_pipeline;

	void dispatch(vk::CommandBuffer& cb, vkte::PipelineHandle pipeline, const PushConstants& pc);
};
