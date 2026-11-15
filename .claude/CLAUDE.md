# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AntSim is a C++20 Vulkan ant colony simulation. Ants search for food, carry it to their nest and leave a food trail in a hash grid that other ants follow; all of it runs in Slang compute shaders, rendered with a graphics pass and an ImGui UI.

There are no unit tests. Validation is interactive — run the application and watch the simulation.

## Build Commands

```bash
cmake -S . -B bDebug -DCMAKE_BUILD_TYPE=Debug
cmake --build bDebug -j$(nproc)
# Run (finds the ant_shaders/ directory walking up from the CWD)
./bDebug/AntSim
```

The first build compiles vkTurboEngine's vendored Slang library, which takes a while. Shaders need no build step: the engine compiles the Slang shaders from source in-process, at startup and on **F5** (or the UI's **Reload Shaders**). `python ant_shaders/compile_shaders.py` is a standalone validator that runs `slangc` over every shader (writing throwaway `.spv` files to the gitignored `ant_shaders/bin/`).

In a Debug build, compiling the shaders at startup takes ~10 s (Debug Slang), and the window only appears (maps in sway) after that. Presenting uses FIFO, which on Wayland blocks while the window isn't shown (other workspace, locked screen), so the loop stalls and doesn't react to closing until it is visible; for headless tests switch `present_settings` in `run_application()` to `eMailbox` temporarily.

Controls: left mouse drag pans (the grabbed point stays under the cursor), the mouse wheel zooms about the cursor, the right mouse button adds food under the cursor or paints/erases walls (the UI's **Right Mouse** tool and **Wall Brush Radius**), **G** toggles the UI, **F5** reloads the shaders.

## Architecture

- `main()` finds `ant_shaders/` and calls `run_application()` (`src/application.cpp`), which creates the `vkte::Engine` and the `WorkContext` and runs the event loop; UI requests (reload shaders) are flags in `AppState` that the loop handles between frames. `AppState::view` (`View`) is the shown part of the world: a center and a height, whose width follows the window's aspect ratio so that world units are square on screen; mouse positions map to the world with `View::to_world()` and `AppState::window_size` (window coordinates, not the swapchain's pixels).
- `WorkContext` (`src/work_context.cpp`) owns the `Simulation` component and records each frame: after `Engine::begin_frame()` it updates the frame's uniform buffer, records the simulation (preceded by filling the buffers with the simulation's start on the first frame and on **Reset Simulation**) and then, after a barrier, the drawing of the hash grid, the ants and the UI (`UI` in `src/ui.cpp`, the ImGui window) with dynamic rendering into one command buffer on the graphics queue; a separate compute queue wouldn't overlap anything, since vkte runs the frames one after another. (Every `Command::submit_*()` of a frame waits for the previous frame's.)
- `Simulation` (`src/simulation.cpp`) is the one `vkte::Component`: `declare_resources()` creates the ants', nest's and hash grid's bindless buffers and declares the pipelines; it builds the push constants and records reset (buffer fills), step and draw.
- The simulation advances by fixed steps of `SIMULATION_TIME_STEP` (`ant_shaders/shared/push_constants.slang`): each frame runs as many steps as fit in the accumulated real time (a frame counts as at most 0.1 s) times `AppState::simulation_speed` (the UI's **Speed**, 0 pauses), each step a dispatch of `step_ants` and `update_hash_grid`. `PushConstants::step` is the step a pass computes (for drawing the steps done); shaders derive the simulated time (`step * SIMULATION_TIME_STEP`) and the random seeds from it, so nothing in the simulation depends on the frame rate. Runs still aren't bitwise reproducible: ants update cells concurrently in `update_hash_grid` (deliberately, so that every ant in a crowded cell acts each step).
- Ant behavior (`ants.slang`) comes from a few physical mechanisms instead of tuned probabilities, each a named constant at the top of the file: ants walk with a heading that drifts randomly; ants without food steer toward the strongest smell (food, else the food trail's amount) of three antennae (left, ahead, right); ants with food steer toward `Ant::nest_estimate`, where they believe the nest is from path integration (it drifts randomly the farther they walk and is corrected within smelling distance of the nest), and lay the food trail, adding the time they spend in a cell to it; trails fade exponentially (`FOOD_TRAIL_HALF_LIFE`), so busy trails grow stronger and the colony converges on short ones. Ants turn back on taking food and on delivering it. An ant whose step would enter a wall turns by multiples of `WALL_TURN_ANGLE` until it is free, so ants slide along walls; antennae smell nothing in walls. There is no nest pheromone: like real foraging ants, only ants carrying food mark the way.
- Walls are a dense bit grid over the whole world (`shared/walls.slang`, `include/walls.slang`; a bit per hash grid cell, 5000×5000 cells = 3 MB), not hash grid cells, so they have no collision gaps; cells outside the world count as walls, which bounds the world. The `paint_walls` pass (`walls.slang`) paints or erases the frame's `WallStroke` (the cursor's way since the last frame, so fast strokes leave no gaps). **Reset Simulation** keeps the walls; **Clear Walls** (and the first frame) empties them.
- Every pipeline takes the same `PushConstants` (`ant_shaders/shared/push_constants.slang`): the bindless buffer handles, which shaders resolve with `vkte::get_buffer<T>()`, and the ant count and hash grid capacity.
- Rendering has no depth attachment, so draw order decides what is on top: the hash grid's full-screen pass first, then the ants.

## Shader Organization

All shaders are Slang in `ant_shaders/`. `ants.slang`, `hash_grid.slang` and `walls.slang` hold the entry points (`[shader("...")]`), several per file: the compute passes and the render pass (`vertex_main`, `fragment_main`) of the ants and of the hash grid, which `vkte::Shader` selects by entry point name. Entry points must not be named like Slang built-ins (`step` fails with "no function found matching entry point name"). `python ant_shaders/compile_shaders.py` compiles every entry point it finds.

`ant_shaders/shared/` holds the data shared with C++ (`Ant`, `HashGridCell`, `Nest`, `UniformBufferData` with its `Visualizations`, which `AppState` holds for the UI to edit, `PushConstants`, `WORKGROUP_SIZE`, and the enum `ColorMap`): Slang modules that C++ includes as headers (`ant_shaders/` is on the include path), made valid C++ by `shared/common.slang` (which aliases `float2`/`float3`/`int2` to glm and defines `AS_CONSTANT`). A shared file that needs another one imports it in Slang and includes it in C++ (`#ifdef __SLANG__`). Flags in buffers are `uint32_t` 0/1, not `bool`, whose size differs between Slang's buffers and C++. `ant_shaders/include/` holds shader-only modules, which add shader-side methods to the shared structs with `extension` (`Nest::get_radius()`, `Visualization::get_color()`), and the `HashGrid` (lookup returning `Optional<uint>` slots; one slot per grid position, keyed by the position packed into a `uint`; a cell is alive while it has food or a food trail of at least `MIN_FOOD_TRAIL`, so nothing ages or frees cells per frame; any slot whose cell isn't alive is free, and a position whose slot holds another position's living cell is wasteland, where nothing is laid. Cells have no locks: ants take food with an atomic decrement, claim a free slot with a compare-exchange on its key and add to the trail with a compare-exchange loop on its float bits. Cells store the trail as of the start of a trail epoch (`FOOD_TRAIL_EPOCH_STEP_COUNT` steps; deposits are divided by how much a trail faded since then, `HashGrid::fade`), and the `fade_food_trails` pass rescales every cell once after each epoch's last step, so fading costs no pass per step), `Random` and the color maps.

Buffers are read through pointers (`vkte::Buffer<T>::get_pointer()`) wherever a shader writes single members, since `vkte::Buffer<T>`'s subscript reads and writes whole elements; atomics cast a member's address to `Atomic<T>*`. Shaders use scalar layout, so C++ structs only need the same members in the same order. Types are written out: no `let`/`var` in Slang (unwrap an `Optional<T>` with `hasValue`/`value`) and no `auto` in C++.

## Dependencies

- `vkTurboEngine` — Vulkan abstraction (git submodule, shared with PhotonDust); it vendors Slang (a nested submodule, `git submodule update --init --recursive`), SDL3, spdlog, ImGui and VMA
- `glm` — math

vkte picks the first suitable GPU, which on the dev laptop is the Intel Iris Xe, not the NVIDIA RTX 4080. The Iris Xe has no float atomic add (`shaderBufferFloat32AtomicAdd`), so shaders don't use it; enabling vkte's `shader_atomic_float` would make it unsuitable.
