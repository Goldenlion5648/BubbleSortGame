#+feature dynamic-literals
package template
//this should be able to be put into the web template with no changes!
import "core:container/queue"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:strings"
import ray "vendor:raylib"

//declare globals:
SCREEN_X_DIM :: 1280
SCREEN_Y_DIM :: 720
should_run_game := true
camera_3d: ray.Camera3D

PipeType :: enum {
	NORMAL = 0,
	DEAD,
	GENERATOR,
	ACCEPTOR,
}

// PipeColors :: enum {
// 	RED,

// }

Pipe :: struct {
	using pos: ray.Vector3,
	pipe_type: PipeType,
}

adj := [6]ray.Vector3 {
	ray.Vector3{0, 1, 0},
	ray.Vector3{1, 0, 0},
	ray.Vector3{-1, 0, 0},
	ray.Vector3{0, 0, 1},
	ray.Vector3{0, 0, -1},
	ray.Vector3{0, -1, 0},
}

level_to_goal_positions: [dynamic][dynamic]ray.Vector3
current_level := 0


main :: proc() {
	using ray
	game_clock := 0

	default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	SetConfigFlags({.VSYNC_HINT})
	InitWindow(i32(SCREEN_X_DIM), i32(SCREEN_Y_DIM), "First Odin Game2")

	last_place_time: f64 = -1000
	last_break_time: f64 = -1000
	place_delay := .25
	tile_dim: f32 = 1
	NON_EXISTANT_POS :: ray.Vector3{1000, 1000, 1000}
	ray.SetTargetFPS(60)
	InitAudioDevice()
	default_font := ray.GetFontDefault()
	DisableCursor()
	board_dim: f32 = 7
	is_flowing := false
	remaining_to_send := 1000
	center_coord := f32(int(board_dim / 2))
	camera_3d = {
		fovy       = 45,
		position   = {board_dim, 5, board_dim},
		projection = .PERSPECTIVE,
		target     = {center_coord, 2, center_coord},
		up         = {0, 1, 0},
	}

	all_pipes := make([dynamic]Pipe, context.allocator)
	// defer delete(all_pipes)
	tile_dims_vector := Vector3{tile_dim, tile_dim, tile_dim}
	tile_dim_halfs := tile_dims_vector / 2
	// defer free(&all_pipes)
	for x: f32 = 0; x < board_dim; x += tile_dim {
		for z: f32 = 0; z < board_dim; z += tile_dim {
			cube_pos := Vector3{f32(x), 0, f32(z)}
			append(&all_pipes, Pipe{cube_pos, .DEAD})
		}
	}
	// defer delete(all_pipes)
	MAX_LEVELS :: 8
	MAX_GOALS :: 5
	current_level = 2

	level_to_goal_positions = make([dynamic][dynamic]Vector3)
	append(&level_to_goal_positions, [dynamic]Vector3{})
	append_elems(
		&level_to_goal_positions[len(level_to_goal_positions) - 1],
		Vector3{center_coord, 4, center_coord},
	)

	append(&level_to_goal_positions, [dynamic]Vector3{})
	append_elems(
		&level_to_goal_positions[len(level_to_goal_positions) - 1],
		Vector3{center_coord - 1, 4, center_coord},
		Vector3{center_coord + 1, 4, center_coord},
	)

	append(&level_to_goal_positions, [dynamic]Vector3{})
	append_elems(
		&level_to_goal_positions[len(level_to_goal_positions) - 1],
		Vector3{center_coord - 1, 4, center_coord},
		Vector3{center_coord + 1, 4, center_coord},
		Vector3{center_coord, 4, center_coord + 1},
		Vector3{center_coord, 5, center_coord},
	)

	generator_pos: Vector3 = {center_coord, 1, center_coord}
	// all_goal_positions : [5]Vector3
	// for i in 0..<len(all_goal_positions) {
	// 	all_goal_positions[i] = NON_EXISTANT_POS
	// }
	goal_pos4: Vector3 = {center_coord, 4, center_coord}
	append(&all_pipes, Pipe{pos = generator_pos, pipe_type = .GENERATOR})
	for goal_pos in level_to_goal_positions[current_level] {
		append(&all_pipes, Pipe{pos = goal_pos, pipe_type = .ACCEPTOR})
	}
	screen_center := Vector2{SCREEN_X_DIM / 2, SCREEN_Y_DIM / 2}
	// defer free(&position_to_pipe)
	pos_to_collected: map[Vector3]int
	for should_run_game {
		check_exit_keys()
		UpdateCamera(&camera_3d, .FREE)
		if IsKeyDown(KeyboardKey.LEFT_SHIFT) {
			up := GetCameraUp(&camera_3d)
			move_speed := 5.4 * GetFrameTime()
			up *= move_speed
			camera_3d.position -= up
			camera_3d.target -= up
		}
		position_to_pipe := make(map[Vector3]Pipe)
		defer delete(position_to_pipe)
		clear(&position_to_pipe)
		for pipe in all_pipes {
			position_to_pipe[pipe.pos] = pipe
		}
		//update
		//drawing
		BeginDrawing()
		ClearBackground(SKYBLUE)
		BeginMode3D(camera_3d)

		pos_to_place_at: Vector3
		camera_ray := GetScreenToWorldRay(screen_center, camera_3d)
		slice.sort_by(all_pipes[:], proc(a, b: Pipe) -> bool {
			return(
				Vector3Distance(a.pos, camera_3d.position) <
				Vector3Distance(b.pos, camera_3d.position) \
			)
		})
		has_hit := false
		existing_pos_being_targeted: Vector3 = NON_EXISTANT_POS
		existing_pos_being_targeted_index: int
		for &pipe, index in all_pipes {
			cube_pos := pipe.pos
			result_ray_collision := GetRayCollisionBox(
				camera_ray,
				BoundingBox{cube_pos - tile_dim_halfs, cube_pos + tile_dim_halfs},
			)
			color_to_use: Color
			switch pipe.pipe_type {
			case .DEAD:
				color_to_use = DARKGRAY
			case .GENERATOR:
				color_to_use = GREEN
			case .NORMAL:
				color_to_use = BROWN
			case .ACCEPTOR:
				color_to_use = RED
			}
			if color_to_use != DARKGRAY {
				// color_to_use.a = 20
			}

			if !has_hit && result_ray_collision.hit {
				pos_to_place_at = cube_pos + (result_ray_collision.normal * tile_dim)
				has_hit = true
				existing_pos_being_targeted_index = index
				existing_pos_being_targeted = cube_pos
			}
			if pipe.pipe_type != .NORMAL {
				DrawCube(cube_pos, tile_dim, tile_dim, tile_dim, color_to_use)
			}
			DrawCubeWires(cube_pos, tile_dim + .01, tile_dim + .01, tile_dim + .01, WHITE)
		}

		if existing_pos_being_targeted != NON_EXISTANT_POS {
			if position_to_pipe[existing_pos_being_targeted].pipe_type == .NORMAL &&
			   (IsMouseButtonPressed(MouseButton.LEFT) ||
					   (IsMouseButtonDown(MouseButton.LEFT) &&
							   GetTime() - last_break_time >= place_delay)) {
				last_break_time = GetTime()
				unordered_remove(&all_pipes, existing_pos_being_targeted_index)
			}
			if IsMouseButtonPressed(MouseButton.RIGHT) ||
			   (IsMouseButtonDown(MouseButton.RIGHT) &&
					   GetTime() - last_place_time >= place_delay) {
				last_place_time = GetTime()
				// TODO: add reject sound
				if pos_to_place_at.x < 0 ||
				   pos_to_place_at.x >= board_dim ||
				   pos_to_place_at.y < 0 ||
				   pos_to_place_at.y >= board_dim * 2 ||
				   pos_to_place_at.z < 0 ||
				   pos_to_place_at.z >= board_dim {

				} else {
					append(&all_pipes, Pipe{pos = pos_to_place_at, pipe_type = .NORMAL})
				}

			}
			buffer: f32 = 0.03
			DrawCubeWires(
				existing_pos_being_targeted + {0, 0.01, 0},
				tile_dim + buffer,
				tile_dim + buffer,
				tile_dim + buffer,
				PINK,
			)
		}
		path_found := get_path(&all_pipes, generator_pos, &level_to_goal_positions[current_level])
		// TEMP:
		is_flowing = true
		// if IsKeyPressed(KeyboardKey.F) {
		// 	fmt.println(path_found)
		// }
		amount_per_round := 5
		if len(path_found) > 0 && is_flowing && remaining_to_send > 0 {
			pos_to_collected[path_found[len(path_found) - 1]] += amount_per_round
			remaining_to_send -= amount_per_round
			fmt.println(pos_to_collected)
		}

		radius: f32 = .4
		side_count: i32 = 8
		/* if len(path_found) > 0 {
			for point, i in path_found[:len(path_found) - 1] {
				DrawCylinderEx(path_found[i], path_found[i + 1], radius, radius, side_count, WHITE)
				DrawCylinderWiresEx(path_found[i], path_found[i + 1], radius, radius, side_count, BLACK)
			}
		} */
		for pos in position_to_pipe {
			found := false
			for offset in adj {
				connected_pos := pos + offset
				if connected_pos in position_to_pipe {
					found = true
					lower := pos
					higher := connected_pos
					if pos.x > connected_pos.x ||
					   pos.y > connected_pos.y ||
					   pos.z > connected_pos.z {
						lower = connected_pos
						higher = pos
					}
					to_add := (higher - lower) * radius / 1.8
					lower -= to_add
					higher += to_add
					DrawCylinderEx(lower, higher, radius, radius, side_count, WHITE)
					DrawCylinderWiresEx(lower, higher, radius, radius, side_count, BLACK)
				}
			}
			if !found {
				DrawSphere(pos, radius, WHITE)
				DrawSphereWires(pos, radius + .01, side_count, side_count, BLACK)
				// DrawCylinderEx(lower, higher, radius, radius, side_count, WHITE)
				// DrawCylinderWiresEx(lower, higher, radius, radius, side_count, BLACK)
			}
		}


		EndMode3D()
		font_size: f32 = 50
		spacing: f32 = 0
		DrawText(fmt.ctprint("Remaining:", remaining_to_send), 10, 10, 24, BLACK)
		for goal_pos in level_to_goal_positions[current_level] {
			cube_screen_pos := GetWorldToScreen(goal_pos, camera_3d)
			DrawText(
				fmt.ctprint(pos_to_collected[goal_pos]),
				i32(cube_screen_pos.x),
				i32(cube_screen_pos.y + tile_dim),
				40,
				BLACK,
			)
		}

		// measured := MeasureTextEx(default_font, "+", font_size, spacing)
		// DrawTextPro(default_font, "+", screen_center, measured / 2, 0, 50, 0, WHITE)
		DrawCircle(i32(screen_center.x), i32(screen_center.y), 5, LIGHTGRAY)
		EndDrawing()
		game_clock += 1
		// if len(path_found) > 0 {
		// 	free(&path_found)
		// }
		free_all(context.temp_allocator)
	}
	delete(all_pipes)
	delete(level_to_goal_positions)
	shutdown()
	free_all()
	reset_tracking_allocator(&tracking_allocator)
}

get_path :: proc(
	all_pipes: ^[dynamic]Pipe,
	start: ray.Vector3,
	goal_positions: ^[dynamic]ray.Vector3,
) -> [dynamic]ray.Vector3 {
	using ray

	all_positions := make([dynamic]Vector3, context.temp_allocator)
	for &pipe in all_pipes {
		append_elem(&all_positions, pipe.pos)
	}
	fringe := make([dynamic][dynamic]Vector3)
	append_elem(&fringe, [dynamic]Vector3{})
	append_elem(&fringe[len(fringe) - 1], start)

	defer {
		for &x in fringe {
			delete(x)
		}
		delete(fringe)
	}
	seen := make([dynamic]Vector3, context.temp_allocator)
	// defer free(&seen)

	bad_ret := make([dynamic]Vector3)
	// defer free(&seen)

	// append_elem(&fringe, start)
	cur_path_copy: [dynamic]Vector3
	fringe_top: for len(fringe) > 0 {
		cur_path := pop_front(&fringe)
		defer delete(cur_path)
		cur := cur_path[len(cur_path) - 1]
		if !slice.contains(all_positions[:], cur) || slice.contains(seen[:], cur) {
			continue
		}
		for &pipe in all_pipes {
			if pipe.pos == cur && pipe.pipe_type == .DEAD {
				continue fringe_top
			}
		}

		append_elem(&seen, cur)
		if slice.contains(goal_positions[:], cur) {
			return cur_path
		}
		if slice.contains(level_to_goal_positions[current_level][:], cur) {
			continue
		}
		get_score :: proc(point: ray.Vector3) -> int {
			score := 0
			if point == {0, 1, 0} {
				score -= 1000
			}
			if point == {0, -1, 0} {
				score += 100_000
			}
			return score + int(rand.float32_range(0, 4))
		}
		slice.sort_by(adj[:], proc(a, b: Vector3) -> bool {
			return get_score(a) < get_score(b)
		})

		for option in adj {
			append_elem(&fringe, [dynamic]Vector3{})
			fringe[len(fringe) - 1] = make([dynamic]Vector3, context.temp_allocator)
			for elem in cur_path {
				append_elem(&fringe[len(fringe) - 1], elem)
			}
			append_elem(&fringe[len(fringe) - 1], cur + option)
		}

	}
	return bad_ret
}

check_exit_keys :: proc() {
	using ray
	if WindowShouldClose() ||
	   (IsKeyDown(KeyboardKey.LEFT_CONTROL) && IsKeyPressed(KeyboardKey.B)) ||
	   IsKeyDown(KeyboardKey.F8) {
		should_run_game = false
	}
}

reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
	err := false

	for _, value in a.allocation_map {
		fmt.printf("%v: Leaked %v bytes\n", value.location, value.size)
		err = true
	}

	mem.tracking_allocator_clear(a)
	return err
}

// In a web build, this is called when browser changes size. Remove the
// `ray.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
	// ray.SetWindowSize(i32(w), i32(h))
}

shutdown :: proc() {
	ray.CloseWindow()
}
