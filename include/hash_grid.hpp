#pragma once

#include "shared/hash_grid.slang"
#include "shared/push_constants.slang"
#include "vkte/component.hpp"
#include "vkte/engine.hpp"
#include "vkte/resource_handles.hpp"

// the cells that hold food and pheromones, hashed by their position
class HashGrid : public vkte::Component
{
public:
	HashGrid(vkte::Engine& engine, uint32_t capacity);
	const char* name() const override { return "hash_grid"; }
	void declare_resources(vkte::ResourceDeclarations& declarations, vkte::MemoryManager& memory_manager, const vkte::FrameSettings& frame_settings) override;
	void destruct(vkte::MemoryManager& memory_manager) override;
	void clear(vk::CommandBuffer& cb, const PushConstants& pc);
	// adds the food of the push constants, ages the pheromones and frees the cells without food whose pheromones expired
	void compute(vk::CommandBuffer& cb, const PushConstants& pc);
	// the hash grid and the nest, covering the screen
	void draw(vk::CommandBuffer& cb, const PushConstants& pc);
	vkte::BufferHandle get_buffer() const { return hash_grid_buffer; }

private:
	vkte::Engine& engine;
	uint32_t capacity;
	vkte::BufferHandle hash_grid_buffer;
	vkte::PipelineHandle clear_pipeline;
	vkte::PipelineHandle render_pipeline;
	vkte::PipelineHandle step_pipeline;

	void dispatch(vk::CommandBuffer& cb, vkte::PipelineHandle pipeline, const PushConstants& pc);
};
