#pragma once

#include <string>
#include "glm/vec2.hpp"

struct ApplicationSettings
{
	// where the shaders are compiled from
	std::string shader_dir;
	glm::ivec2 window_resolution = glm::ivec2(1000, 1000);
};

int run_application(const ApplicationSettings& settings);
