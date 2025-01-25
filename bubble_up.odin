package template
//this should be able to be put into the web template with no changes!
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

main :: proc() {
	using ray
	game_clock := 0

	default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)
	camera_3d = {
		fovy       = 45,
		position   = {5, 5, 5},
		projection = .PERSPECTIVE,
		target     = {0, 2, 0},
		up         = {0, 1, 0},
	}

	SetConfigFlags({.VSYNC_HINT})
	InitWindow(i32(SCREEN_X_DIM), i32(SCREEN_Y_DIM), "First Odin Game2")

	tile_dim: f32 = 1
	NON_EXISTANT_POS :: ray.Vector3{1000, 1000, 1000}
	ray.SetTargetFPS(60)
	InitAudioDevice()
	default_font := ray.GetFontDefault()
	DisableCursor()
	board_dim: f32 = 5

	all_pipes := make([dynamic]Pipe)
	tile_dims_vector := Vector3{tile_dim, tile_dim, tile_dim}
	tile_dim_halfs := tile_dims_vector / 2
	// defer free(&all_pipes)
	for x := -board_dim / 2; x <= board_dim; x += tile_dim {
		for z := -board_dim / 2; z <= board_dim; z += tile_dim {
			cube_pos := Vector3{f32(x), 0, f32(z)}
			append(&all_pipes, Pipe{cube_pos, .DEAD})
		}
	}
	screen_center := Vector2{SCREEN_X_DIM / 2, SCREEN_Y_DIM / 2}

	for should_run_game {
		check_exit_keys()
		UpdateCamera(&camera_3d, .FIRST_PERSON)
		//update
		//drawing
		BeginDrawing()
		ClearBackground(SKYBLUE)
		BeginMode3D(camera_3d)
		DrawGrid(10, tile_dim)
		// for y in 0..<board_dim {
		// for x := -board_dim/2; x < board_dim; x := tile_dim
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
			color_to_use := DARKGRAY if pipe.pipe_type == .DEAD else GREEN
			if !has_hit && result_ray_collision.hit {
				pos_to_place_at = cube_pos + (result_ray_collision.normal * tile_dim)
				has_hit = true
				existing_pos_being_targeted_index = index
				existing_pos_being_targeted = cube_pos
			}
			DrawCube(cube_pos, tile_dim, tile_dim, tile_dim, color_to_use)
			DrawCubeWires(cube_pos, tile_dim, tile_dim, tile_dim, WHITE)
		}
		if existing_pos_being_targeted != NON_EXISTANT_POS {
			if IsMouseButtonPressed(MouseButton.LEFT) {
				unordered_remove(&all_pipes, existing_pos_being_targeted_index)
			}
			if IsMouseButtonPressed(MouseButton.RIGHT) {
				append(&all_pipes, Pipe{pos = pos_to_place_at, pipe_type = .NORMAL})
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


		EndMode3D()
		font_size: f32 = 50
		spacing: f32 = 0
		measured := MeasureTextEx(default_font, "+", font_size, spacing)
		// DrawTextPro(default_font, "+", screen_center, measured / 2, 0, 50, 0, WHITE)
		DrawCircle(i32(screen_center.x), i32(screen_center.y), 5, LIGHTGRAY)
		EndDrawing()
		game_clock += 1
		free_all(context.temp_allocator)
	}
	shutdown()
	free_all()
	reset_tracking_allocator(&tracking_allocator)
}

check_exit_keys :: proc() {
	using ray
	if WindowShouldClose() ||
	   (IsKeyDown(KeyboardKey.LEFT_CONTROL) && IsKeyPressed(KeyboardKey.B)) ||
	   IsKeyDown(KeyboardKey.F8) ||
	   IsKeyDown(KeyboardKey.LEFT_ALT) {
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
