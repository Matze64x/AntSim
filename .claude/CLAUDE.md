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

Controls: left mouse drag pans (the view follows the cursor), the mouse wheel zooms, the right mouse button adds food under the cursor, **G** toggles the UI, **F5** reloads the shaders.

## Architecture

- `main()` finds `ant_shaders/` and calls `run_application()` (`src/application.cpp`), which creates the `vkte::Engine` and the `WorkContext` and runs the event loop; UI requests (reload shaders) are flags in `AppState` that the loop handles between frames.
- `WorkContext` (`src/work_context.cpp`) owns the two components and records each frame: after `Engine::begin_frame()` it updates the frame's uniform buffer, records the simulation into the frame's compute command buffer (on the first frame preceded by the clear passes), which signals a timeline semaphore that the graphics submission waits for, then draws the ants, the hash grid and the UI with dynamic rendering. vkte orders frames itself (every `Command::submit_*()` of a frame waits for the previous frame's).
- `Ants` and `HashGrid` (`src/ants.cpp`, `src/hash_grid.cpp`) are `vkte::Component`s: `declare_resources()` creates their bindless buffers and declares their pipelines; they record clear, compute and draw.
- Every pipeline takes the same `PushConstants` (`ant_shaders/shared/push_constants.slang`): the bindless buffer handles, which shaders resolve with `vkte::get_buffer<T>()`, and the ant count and hash grid capacity.
- Draw order matters: vkte pipelines always test depth with `Less`, so the ants are drawn first and the hash grid's full-screen pass at the same depth fills only the rest.

## Shader Organization

All shaders are Slang in `ant_shaders/`. `ants.slang` and `hash_grid.slang` hold the entry points (`[shader("...")]`), several per file: the clear, step and render passes of each component, which `vkte::Shader` selects by entry point name. Entry points must not be named like Slang built-ins (`step` fails with "no function found matching entry point name"). `python ant_shaders/compile_shaders.py` compiles every entry point it finds.

`ant_shaders/shared/` holds the data shared with C++ (`Ant`, `HashGridCell`, `Nest`, `UniformBufferData` with its `Visualization`s, `PushConstants`, `WORKGROUP_SIZE`, and the enums `TargetPriority`, `Pheromone`, `ColorMap`): Slang modules that C++ includes as headers (`ant_shaders/` is on the include path), made valid C++ by `shared/common.slang` (which aliases `float2`/`float3`/`int2` to glm and defines `AS_CONSTANT`). A shared file that needs another one imports it in Slang and includes it in C++ (`#ifdef __SLANG__`). Flags in buffers are `uint32_t` 0/1, not `bool`, whose size differs between Slang's buffers and C++. `ant_shaders/include/` holds shader-only modules, which add shader-side methods to the shared structs with `extension` (`Nest::get_radius()`, `Visualization::get_color()`), and the `HashGrid` (lookup and per-cell locking, returning `Optional<uint>` slots), `AntTime`, `Random` and the color maps.

Buffers are read through pointers (`vkte::Buffer<T>::get_pointer()`) wherever a shader writes single members, since `vkte::Buffer<T>`'s subscript reads and writes whole elements; atomics cast a member's address to `Atomic<T>*`. Shaders use scalar layout, so C++ structs only need the same members in the same order. Slang's `&&` and `||` short-circuit, which the random draws in conditions rely on.

## Dependencies

- `vkTurboEngine` — Vulkan abstraction (git submodule, shared with PhotonDust); it vendors Slang (a nested submodule, `git submodule update --init --recursive`), SDL3, spdlog, ImGui and VMA
- `glm` — math
