# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AntSim is a C++20 Vulkan ant colony simulation. Ants search for food, carry it to their nest and leave pheromones in a hash grid that other ants follow; all of it runs in Slang compute shaders, rendered with a graphics pass and an ImGui UI.

There are no unit tests. Validation is interactive — run the application and watch the simulation.

## Build Commands

```bash
cmake -S . -B bDebug -DCMAKE_BUILD_TYPE=Debug
cmake --build bDebug -j$(nproc)
# Run (finds the ant_shaders/ directory walking up from the CWD)
./bDebug/AntSim
```

The first build compiles vkTurboEngine's vendored Slang library, which takes a while. Shaders need no build step: the engine compiles the Slang shaders from source in-process, at startup and on **F5** (or the UI's **Reload Shaders**). `python ant_shaders/compile_shaders.py` is a standalone validator that runs `slangc` over every shader (writing throwaway `.spv` files to the gitignored `ant_shaders/bin/`).

In a Debug build, compiling the shaders at startup takes ~10 s (Debug Slang), so the window stays black meanwhile. Presenting uses FIFO, which on Wayland blocks while the window isn't shown (other workspace, locked screen), so the loop stalls and doesn't react to closing until it is visible; for headless tests switch `present_settings` in `run_application()` to `eMailbox` temporarily.

Controls: left mouse drag pans (the grabbed point stays under the cursor), the mouse wheel zooms about the cursor, the right mouse button adds food under the cursor, **G** toggles the UI, **F5** reloads the shaders.

## Architecture

- `main()` finds `ant_shaders/` and calls `run_application()` (`src/application.cpp`), which creates the `vkte::Engine` and the `WorkContext` and runs the event loop; UI requests (reload shaders) are flags in `AppState` that the loop handles between frames. `AppState::view` (`View`) is the shown part of the world: a center and a height, whose width follows the window's aspect ratio so that world units are square on screen; mouse positions map to the world with `View::to_world()` and `AppState::window_size` (window coordinates, not the swapchain's pixels).
- `WorkContext` (`src/work_context.cpp`) owns the `Simulation` component and records each frame: after `Engine::begin_frame()` it updates the frame's uniform buffer, records the simulation (preceded by filling the buffers with the simulation's start on the first frame and on **Reset Simulation**) and then, after a barrier, the drawing of the ants, the hash grid and the UI with dynamic rendering into one command buffer on the graphics queue; a separate compute queue wouldn't overlap anything, since vkte runs the frames one after another. (Every `Command::submit_*()` of a frame waits for the previous frame's.)
- `Simulation` (`src/simulation.cpp`) is the one `vkte::Component`: `declare_resources()` creates the ants', nest's and hash grid's bindless buffers and declares the pipelines; it builds the push constants and records reset (buffer fills), step and draw.
- Every pipeline takes the same `PushConstants` (`ant_shaders/shared/push_constants.slang`): the bindless buffer handles, which shaders resolve with `vkte::get_buffer<T>()`, and the ant count and hash grid capacity.
- Rendering has no depth attachment, so draw order decides what is on top: the hash grid's full-screen pass first, then the ants.

## Shader Organization

All shaders are Slang in `ant_shaders/`. `ants.slang` and `hash_grid.slang` hold the entry points (`[shader("...")]`), several per file: the compute passes and the render pass (`vertex_main`, `fragment_main`) of the ants and of the hash grid, which `vkte::Shader` selects by entry point name. Entry points must not be named like Slang built-ins (`step` fails with "no function found matching entry point name"). `python ant_shaders/compile_shaders.py` compiles every entry point it finds.

`ant_shaders/shared/` holds the data shared with C++ (`Ant`, `HashGridCell`, `Nest`, `UniformBufferData` with its `Visualizations`, which `AppState` holds for the UI to edit, `PushConstants`, `WORKGROUP_SIZE`, and the enums `TargetPriority`, `Pheromone`, `ColorMap`): Slang modules that C++ includes as headers (`ant_shaders/` is on the include path), made valid C++ by `shared/common.slang` (which aliases `float2`/`float3`/`int2` to glm and defines `AS_CONSTANT`). A shared file that needs another one imports it in Slang and includes it in C++ (`#ifdef __SLANG__`). Flags in buffers are `uint32_t` 0/1, not `bool`, whose size differs between Slang's buffers and C++. `ant_shaders/include/` holds shader-only modules, which add shader-side methods to the shared structs with `extension` (`Nest::get_radius()`, `Visualization::get_color()`), and the `HashGrid` (lookup and per-cell locking, returning `Optional<uint>` slots; a cell stores when its pheromone was laid and is alive while it has food or an unexpired pheromone, so nothing ages or frees cells per frame, and any slot whose cell isn't alive is free), `AntTime`, `Random` and the color maps.

Buffers are read through pointers (`vkte::Buffer<T>::get_pointer()`) wherever a shader writes single members, since `vkte::Buffer<T>`'s subscript reads and writes whole elements; atomics cast a member's address to `Atomic<T>*`. Shaders use scalar layout, so C++ structs only need the same members in the same order. Slang's `&&` and `||` short-circuit, which the random draws in conditions rely on.

## Dependencies

- `vkTurboEngine` — Vulkan abstraction (git submodule, shared with PhotonDust); it vendors Slang (a nested submodule, `git submodule update --init --recursive`), SDL3, spdlog, ImGui and VMA
- `glm` — math
