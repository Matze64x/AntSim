#pragma once

#include <filesystem>
#include <string>
#include "glm/vec2.hpp"

struct ApplicationSettings
{
	// where the shaders are compiled from
	std::string shader_dir;
	// the map to start from (see Map), none if empty
	std::filesystem::path map_path;
	glm::ivec2 window_resolution = glm::ivec2(1000, 1000);
};

int run_application(const ApplicationSettings& settings);
