#+feature dynamic-literals
package game
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
all_pipes: [dynamic]Pipe
screen_center := ray.Vector2{SCREEN_X_DIM / 2, SCREEN_Y_DIM / 2}
NON_EXISTANT_POS :: ray.Vector3{1000, 1000, 1000}

tile_dims_vector: ray.Vector3
tile_dim_halfs: ray.Vector3
last_place_time: f64 = -1000
last_break_time: f64 = -1000
tile_dim: f32 : 1
place_delay :: .25
board_dim: f32
remaining_to_send: int
DEFAULT_REMAINING_TO_SEND :: 400
center_coord: f32
generator_pos: ray.Vector3
pos_to_remaining_needed: map[ray.Vector3]int
game_clock := 0
time_to_advance := 100000000
is_advancing := false
tracking_allocator: mem.Tracking_Allocator
ACCEPTOR_CAP :: 100
is_cheat_mode := false

//sounds
level_complete_sound: ray.Sound
place_sound: ray.Sound
deny_sound: ray.Sound

init :: proc() {
	using ray

	default_allocator := context.allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	SetConfigFlags({.VSYNC_HINT})
	InitWindow(i32(SCREEN_X_DIM), i32(SCREEN_Y_DIM), "First Odin Game2")
	is_cheat_mode = ODIN_OS == .Windows
	// fmt.println(is_cheat_mode)

	tile_dims_vector = Vector3{tile_dim, tile_dim, tile_dim}
	tile_dim_halfs = tile_dims_vector / 2

	ray.SetTargetFPS(60)
	InitAudioDevice()
	default_font := ray.GetFontDefault()
	DisableCursor()
	board_dim = 7
	center_coord = f32(int(board_dim / 2))
	generator_pos = {center_coord, 1, center_coord}

	// load sounds
	level_complete_sound = LoadSound("assets/bell.wav")
	place_sound = LoadSound("assets/place.wav")
	deny_sound = LoadSound("assets/deny.wav")

	camera_3d = {
		fovy       = 45,
		position   = {board_dim, 5, board_dim},
		projection = .PERSPECTIVE,
		target     = {center_coord, 2, center_coord},
		up         = {0, 1, 0},
	}

	all_pipes = make([dynamic]Pipe, context.allocator)
	// defer delete(all_pipes)

	// defer free(&all_pipes)
	// reset_pipes()
	// defer delete(all_pipes)
	MAX_LEVELS :: 8
	MAX_GOALS :: 5
	current_level = 0

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
		Vector3{center_coord - 1, 6, center_coord},
		Vector3{center_coord + 2, 5, center_coord},
		// Vector3{center_coord, 5, center_coord},
	)

	append(&level_to_goal_positions, [dynamic]Vector3{})
	append_elems(
		&level_to_goal_positions[len(level_to_goal_positions) - 1],
		Vector3{center_coord - 1, 4, center_coord},
		Vector3{center_coord + 1, 4, center_coord},
		Vector3{center_coord, 5, center_coord},
	)

	append(&level_to_goal_positions, [dynamic]Vector3{})
	append_elems(
		&level_to_goal_positions[len(level_to_goal_positions) - 1],
		Vector3{center_coord - 1, 4, center_coord},
		Vector3{center_coord + 1, 4, center_coord},
		Vector3{center_coord, 4, center_coord - 1},
		Vector3{center_coord, 5, center_coord},
	)

	reset_pipes()
	reset_remaining_bubbles()
}

play_sound_with_variance :: proc(sound: ray.Sound) {
	ray.SetSoundPitch(sound, rand.float32_range(.8, 1.2))
	ray.PlaySound(sound)
}

reset_pipes :: proc() {
	using ray
	clear(&all_pipes)
	clear(&pos_to_remaining_needed)

	// floor
	for x: f32 = 0; x < board_dim; x += tile_dim {
		for z: f32 = 0; z < board_dim; z += tile_dim {
			cube_pos := Vector3{f32(x), 0, f32(z)}
			append(&all_pipes, Pipe{cube_pos, .DEAD})
		}
	}
	generator_pos = {center_coord, 1, center_coord}
	append(&all_pipes, Pipe{pos = generator_pos, pipe_type = .GENERATOR})
	default_amount_needed_to_satisfy_goal := 100
	for goal_pos in level_to_goal_positions[current_level] {
		append(&all_pipes, Pipe{pos = goal_pos, pipe_type = .ACCEPTOR})
		pos_to_remaining_needed[goal_pos] = default_amount_needed_to_satisfy_goal
	}
}

reset_remaining_bubbles :: proc() {
	remaining_to_send = DEFAULT_REMAINING_TO_SEND
}

advance_level :: proc() {
	current_level += 1
	setup_for_level()
}

setup_for_level :: proc() {
	is_advancing = false
	reset_pipes()
	reset_remaining_bubbles()

}


update :: proc() {
	using ray
	check_exit_keys()
	// UpdateCamera(&camera_3d, .FIRST_PERSON)
	if is_cheat_mode {
		if IsKeyPressed(.BACKSPACE) && current_level > 0 {
			current_level -= 1
			setup_for_level()
		}
		if IsKeyPressed(.BACKSLASH) && current_level + 1 < len(level_to_goal_positions) {
			current_level += 1
			setup_for_level()
		}
	}

	if IsKeyPressed(.R) {
		reset_pipes()
		reset_remaining_bubbles()
	}


	distance: f32 = 5.4
	move_speed := 5.4 * GetFrameTime()
	move_amount := GetCameraUp(&camera_3d) * move_speed
	if IsKeyDown(KeyboardKey.W) {
		CameraMoveForward(&camera_3d, move_speed, true)
	}
	if IsKeyDown(KeyboardKey.A) {
		CameraMoveRight(&camera_3d, -move_speed, GetFrameTime())
	}
	if IsKeyDown(KeyboardKey.S) {
		CameraMoveForward(&camera_3d, -move_speed, true)
	}
	if IsKeyDown(KeyboardKey.D) {
		CameraMoveRight(&camera_3d, move_speed, GetFrameTime())
	}
	rotate_speed :f32= 0.2
	CameraYaw(&camera_3d, -rotate_speed*GetMouseDelta().x*GetFrameTime(), false)
	CameraPitch(&camera_3d, -rotate_speed*GetMouseDelta().y*GetFrameTime(), true, false, false)
	// GetMouseDelta()
	// CameraMoveForward()

	if IsKeyDown(KeyboardKey.LEFT_SHIFT) || IsKeyDown(KeyboardKey.Q) {
		camera_3d.position -= move_amount
		camera_3d.target -= move_amount
	}
	if IsKeyDown(KeyboardKey.SPACE) || IsKeyDown(KeyboardKey.E) {
		camera_3d.position += move_amount
		camera_3d.target += move_amount
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
		if pipe.pipe_type == .NORMAL {
			result_ray_collision = GetRayCollisionBox(
				camera_ray,
				BoundingBox{cube_pos - tile_dim_halfs * .8, cube_pos + tile_dim_halfs * .8},
			)
		}

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
			if cube_pos in pos_to_remaining_needed && pos_to_remaining_needed[cube_pos] == 0 {
				color_to_use = PINK
			}
		}
		if color_to_use != DARKGRAY {
			// color_to_use.a = 20
		}

		if !has_hit && result_ray_collision.hit {
			// fmt.println(result_ray_collision.normal)
			closest := NON_EXISTANT_POS
			highest: f32 = -10
			for dir in adj {
				temp := Vector3DotProduct(dir, result_ray_collision.normal)
				if temp > highest {
					highest = temp
					closest = dir
				}
			}
			pos_to_place_at = cube_pos + (closest * tile_dim)
			has_hit = true
			existing_pos_being_targeted_index = index
			existing_pos_being_targeted = cube_pos
		}
		if pipe.pipe_type == .ACCEPTOR || pipe.pipe_type == .GENERATOR {
			DrawSphere(cube_pos, tile_dim / 2, color_to_use)
		}
		if pipe.pipe_type == .DEAD {
			DrawCube(cube_pos, tile_dim, tile_dim, tile_dim, color_to_use)
		}

		if pipe.pipe_type == .NORMAL {
			// DrawCubeWires(cube_pos, tile_dim *.8, tile_dim *.8, tile_dim *.8, WHITE)
		} else {
			DrawCubeWires(cube_pos, tile_dim + .01, tile_dim + .01, tile_dim + .01, WHITE)
		}
	}

	if existing_pos_being_targeted != NON_EXISTANT_POS {
		if position_to_pipe[existing_pos_being_targeted].pipe_type == .NORMAL &&
		   (IsMouseButtonPressed(MouseButton.LEFT) ||
				   (IsMouseButtonDown(MouseButton.LEFT) &&
						   GetTime() - last_break_time >= place_delay)) {
			last_break_time = GetTime()
			unordered_remove(&all_pipes, existing_pos_being_targeted_index)
			play_sound_with_variance(place_sound)
		}
		if IsMouseButtonPressed(MouseButton.RIGHT) ||
		   (IsMouseButtonDown(MouseButton.RIGHT) && GetTime() - last_place_time >= place_delay) {
			last_place_time = GetTime()
			// TODO: add reject sound
			if pos_to_place_at.x < 0 ||
			   pos_to_place_at.x >= board_dim ||
			   pos_to_place_at.y < 0 ||
			   pos_to_place_at.y >= board_dim * 2 ||
			   pos_to_place_at.z < 0 ||
			   pos_to_place_at.z >= board_dim {
				play_sound_with_variance(deny_sound)
			} else {
				if pos_to_place_at not_in position_to_pipe {
					append(&all_pipes, Pipe{pos = pos_to_place_at, pipe_type = .NORMAL})
					play_sound_with_variance(place_sound)
				}
			}

		}
		buffer: f32 = 0.03

		box_to_use: Vector3 = Vector3{tile_dim + buffer, tile_dim + buffer, tile_dim + buffer}
		if position_to_pipe[existing_pos_being_targeted].pipe_type == .NORMAL {
			// make it smaller when a pipe is being looked at
			box_to_use *= .8
		}
		DrawCubeWiresV(existing_pos_being_targeted + {0, 0.01, 0}, box_to_use, PINK)
	}
	path_found := get_path(&all_pipes, generator_pos, &level_to_goal_positions[current_level])
	// if IsKeyPressed(KeyboardKey.F) {
	// 	fmt.println(path_found)
	// }
	amount_per_round := 5
	if len(path_found) > 0 && remaining_to_send > 0 {
		if pos_to_remaining_needed[path_found[len(path_found) - 1]] - amount_per_round >= 0 {
			pos_to_remaining_needed[path_found[len(path_found) - 1]] -= amount_per_round
		}
		remaining_to_send -= amount_per_round
	}

	satisfied_collector_count := 0
	for pos, amount in pos_to_remaining_needed {
		if amount == 0 {
			satisfied_collector_count += 1
		}
	}
	if !is_advancing && satisfied_collector_count == len(level_to_goal_positions[current_level]) {
		// TODO: add some delay
		play_sound_with_variance(level_complete_sound)
		time_to_advance = game_clock + 90
		is_advancing = true
		// advance_level()
	}

	radius: f32 = .4
	side_count: i32 = 8

	for pos, pipe in position_to_pipe {
		found := false
		if pipe.pipe_type == .DEAD do continue

		for offset in adj {
			connected_pos := pos + offset
			if connected_pos in position_to_pipe &&
			   position_to_pipe[connected_pos].pipe_type != .DEAD {
				found = true
				lower := pos
				higher := connected_pos
				if pos.x > connected_pos.x || pos.y > connected_pos.y || pos.z > connected_pos.z {
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
	DrawText(fmt.ctprint("Level:", current_level + 1), 10, 40, 24, BLACK)
	for goal_pos in level_to_goal_positions[current_level] {
		cube_screen_pos := GetWorldToScreen(goal_pos, camera_3d)
		DrawText(
			fmt.ctprint(pos_to_remaining_needed[goal_pos]),
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
	if game_clock >= time_to_advance {
		advance_level()
		time_to_advance = max(int) / 2
	}
	// if len(path_found) > 0 {
	// 	free(&path_found)
	// }
	free_all(context.temp_allocator)
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

	bad_ret := make([dynamic]Vector3)

	// append_elem(&fringe, start)
	cur_path_copy: [dynamic]Vector3
	fringe_top: for len(fringe) > 0 {
		cur_path := pop(&fringe)
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
		slice.reverse_sort_by(adj[:], proc(a, b: Vector3) -> bool {
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
	if !should_run() ||
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

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if ray.WindowShouldClose() {
			return false
		}
	}

	return true
}


main :: proc() {
	using ray
	init()
	for should_run_game {
		update()
	}
	delete(all_pipes)
	for x in level_to_goal_positions {
		delete(x)
	}
	delete(level_to_goal_positions)
	shutdown()
	free_all()
	reset_tracking_allocator(&tracking_allocator)
}
