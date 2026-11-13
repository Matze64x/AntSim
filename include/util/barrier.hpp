#pragma once

#include "vulkan/vulkan.hpp"

// makes what earlier compute dispatches wrote visible to later ones, and lets later ones write what earlier ones read
inline void compute_to_compute_barrier(vk::CommandBuffer& cb)
{
	const vk::MemoryBarrier2 barrier(vk::PipelineStageFlagBits2::eComputeShader, vk::AccessFlagBits2::eShaderWrite, vk::PipelineStageFlagBits2::eComputeShader, vk::AccessFlagBits2::eShaderRead | vk::AccessFlagBits2::eShaderWrite);
	cb.pipelineBarrier2(vk::DependencyInfo().setMemoryBarriers(barrier));
}
