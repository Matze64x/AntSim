import include.hash_grid;
import include.walls;
import shared.push_constants;
import shared.walls;
import vkte;

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

float get_distance_to_line(float2 pos, float2 from, float2 to)
{
	const float2 line = to - from;
	const float t = dot(line, line) > 0.0 ? saturate(dot(pos - from, line) / dot(line, line)) : 0.0;
	return distance(pos, from + t * line);
}

// Paints or erases the walls of the cells that the push constants' wall stroke covers. A thread per cell of the stroke's
// bounding box, starting at its minimum.
[shader("compute")]
[numthreads(8, 8, 1)]
void paint_walls(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
	const WallStroke stroke = pc.wall_stroke;
	const int2 index = get_hash_grid_pos(min(stroke.from, stroke.to) - stroke.radius) + int2(dispatch_thread_id.xy);
	const Walls walls = Walls(vkte::get_buffer<uint32_t>(pc.walls).get_pointer());
	if (!walls.is_in_world(index) || get_distance_to_line(get_hash_grid_cell_pos(index), stroke.from, stroke.to) > stroke.radius) return;
	walls.set_wall(index, stroke.brush == WallBrush::Paint);
}
