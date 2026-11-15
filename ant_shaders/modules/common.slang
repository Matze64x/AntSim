#pragma once

// Included by the files in modules/ that C++ also includes as headers, so that the data both sides read has a single
// definition. In C++ this aliases the Slang names that those files use.

#ifdef __SLANG__

#define AS_CONSTANT static const
// a free function that both sides use
#define AS_FUNCTION

#else // __SLANG__

#include <cstdint>
#include "glm/vec2.hpp"
#include "glm/vec3.hpp"
#define AS_CONSTANT inline constexpr
#define AS_FUNCTION inline

using float2 = glm::vec2;
using float3 = glm::vec3;
using int2 = glm::ivec2;

#endif // __SLANG__
