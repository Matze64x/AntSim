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
	// records emptying every cell
	void reset(vk::CommandBuffer& cb);
	// puts the push constants' food into the cell at its position
	void add_food(vk::CommandBuffer& cb, const PushConstants& pc);
	// the hash grid and the nest, covering the screen
	void draw(vk::CommandBuffer& cb, const PushConstants& pc);
	vkte::BufferHandle get_buffer() const { return hash_grid_buffer; }

private:
	vkte::Engine& engine;
	uint32_t capacity;
	vkte::BufferHandle hash_grid_buffer;
	vkte::PipelineHandle render_pipeline;
	vkte::PipelineHandle add_food_pipeline;
};
