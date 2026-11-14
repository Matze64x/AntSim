#pragma once

#include "glm/vec2.hpp"
#include "shared/push_constants.slang"
#include "vkte/component.hpp"
#include "vkte/engine.hpp"
#include "vkte/resource_handles.hpp"

// the ants, their nest and the hash grid of cells that hold food and pheromones, with the pipelines that simulate and draw them
class Simulation : public vkte::Component
{
public:
	Simulation(vkte::Engine& engine, uint32_t ant_count, uint32_t hash_grid_capacity);
	const char* name() const override { return "simulation"; }
	void declare_resources(vkte::ResourceDeclarations& declarations, vkte::MemoryManager& memory_manager, const vkte::FrameSettings& frame_settings) override;
	void destruct(vkte::MemoryManager& memory_manager) override;
	// of all pipelines, for a frame that adds food_amount food at food_pos (none if it is 0), at the simulation step
	PushConstants get_push_constants(vkte::BufferHandle uniform_buffer, glm::vec2 food_pos, int32_t food_amount, uint32_t step) const;
	// records filling the buffers with the simulation's start: no ants yet (they start at the nest), a level 1 nest and empty cells
	void reset(vk::CommandBuffer& cb);
	// records putting the push constants' food into the cell at its position
	void add_food(vk::CommandBuffer& cb, const PushConstants& pc);
	// records the simulation step pc.step: moving the ants, then letting them mark and take food from the cells
	void step(vk::CommandBuffer& cb, const PushConstants& pc);
	// records drawing the hash grid and the nest covering the screen, and the ants on top
	void draw(vk::CommandBuffer& cb, const PushConstants& pc);

private:
	vkte::Engine& engine;
	uint32_t ant_count;
	uint32_t hash_grid_capacity;
	vkte::BufferHandle ants_buffer;
	vkte::BufferHandle nest_buffer;
	vkte::BufferHandle hash_grid_buffer;
	vkte::PipelineHandle add_food_pipeline;
	vkte::PipelineHandle step_ants_pipeline;
	vkte::PipelineHandle update_hash_grid_pipeline;
	vkte::PipelineHandle hash_grid_render_pipeline;
	vkte::PipelineHandle ants_render_pipeline;

	void bind(vk::CommandBuffer& cb, vkte::PipelineHandle pipeline, const PushConstants& pc, vk::ShaderStageFlags stages);
};
