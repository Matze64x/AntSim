#include <filesystem>
#include <string>
#include <vector>

#include "spdlog/sinks/basic_file_sink.h"
#include "spdlog/sinks/stdout_color_sinks.h"
#include "spdlog/spdlog.h"

#include "antlog.hpp"
#include "application.hpp"

static std::string find_ancestor_dir(const std::filesystem::path& start, const std::string& name)
{
	std::error_code ec;
	std::filesystem::path p = std::filesystem::absolute(start, ec);
	if (ec) return "";
	while (true)
	{
		std::filesystem::path candidate = p / name;
		if (std::filesystem::is_directory(candidate, ec)) return candidate.string();
		std::filesystem::path parent = p.parent_path();
		if (parent == p) return "";
		p = parent;
	}
}

int main(int argc, char* argv[])
{
	std::vector<spdlog::sink_ptr> sinks;
	sinks.push_back(std::make_shared<spdlog::sinks::stderr_color_sink_mt>());
	sinks[0]->set_pattern("%^[%Y-%m-%d %T.%e] [%L]%$ %v");
	// vkte logs from its worker threads too, e.g. when shaders fail to compile
	sinks.push_back(std::make_shared<spdlog::sinks::basic_file_sink_mt>("ant.log", true));
	sinks[1]->set_pattern("[%Y-%m-%d %T.%e] [%L] %v");
	const std::shared_ptr<spdlog::logger> combined_logger = std::make_shared<spdlog::logger>("default_logger", sinks.begin(), sinks.end());
	spdlog::set_default_logger(combined_logger);
	spdlog::set_level(spdlog::level::debug);

	ApplicationSettings settings;
	settings.shader_dir = find_ancestor_dir(std::filesystem::current_path(), "ant_shaders");
	if (settings.shader_dir.empty())
	{
		antlog::error("No 'ant_shaders' directory found in the current working directory or any of its ancestors");
		return 1;
	}
	antlog::info("Using shader directory: {}", settings.shader_dir);
	return run_application(settings);
}
