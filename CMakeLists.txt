cmake_minimum_required(VERSION 3.19)
project(AntSim)
set(CMAKE_CXX_STANDARD 20)

find_program(CCACHE_PROGRAM ccache)
if (CCACHE_PROGRAM)
	set(CMAKE_CXX_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
endif()

if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
	find_program(MOLD_PROGRAM mold)
	find_program(LLD_PROGRAM ld.lld)
	if (MOLD_PROGRAM)
		add_link_options(-fuse-ld=mold)
	elseif (LLD_PROGRAM)
		add_link_options(-fuse-ld=lld)
	endif()
endif()

set(VKTE_DIR "${PROJECT_SOURCE_DIR}/dependencies/vkTurboEngine")

set(ENABLE_VKTE_LOGGING ON)
add_subdirectory(${VKTE_DIR})

set(SOURCE_FILES
	src/ants.cpp
	src/application.cpp
	src/hash_grid.cpp
	src/work_context.cpp
	src/util/random_generator.cpp
)

add_executable(AntSim src/main.cpp ${SOURCE_FILES})
target_include_directories(AntSim PRIVATE "${PROJECT_SOURCE_DIR}/include"
	"${PROJECT_SOURCE_DIR}/ant_shaders/"
	"${PROJECT_SOURCE_DIR}/dependencies/"
	"${VKTE_DIR}/include/"
)
target_link_libraries(AntSim PRIVATE vkte)
if (CMAKE_IMPORT_LIBRARY_SUFFIX)
	add_custom_command(TARGET AntSim POST_BUILD
		COMMAND ${CMAKE_COMMAND} -E copy_if_different
		$<TARGET_RUNTIME_DLLS:AntSim>
		$<TARGET_FILE_DIR:AntSim>
		COMMAND_EXPAND_LISTS
	)
endif()
