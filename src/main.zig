const std = @import("std");

const gl = @import("gl");
const glfw = @import("glfw");

const engine = @import("engine.zig");
const debug = @import("debug.zig");
const Camera = @import("camera.zig").Camera;
const m = @import("math.zig");
const voxel = @import("voxel.zig");

var output_texture: engine.Texture = undefined;

fn resizeOutputTexture(width: c_int, height: c_int) void {
    output_texture.resize(0, width, height);
}

var compute_program: engine.ComputeProgram = undefined;

var camera: Camera = undefined;
fn updateCamera(_: c_int, _: c_int) void {
    camera.update();
    camera.applyUniforms(engine.ComputeProgram, &compute_program);
}

var sensitivity: f32 = 0.05;

var prev_xpos: f64 = 0;
var prev_ypos: f64 = 0;
var first_input = true;

fn cursorCallback(_: *glfw.Window, xpos: f64, ypos: f64) callconv(.c) void {
    if (first_input) {
        prev_xpos = xpos;
        prev_ypos = ypos;
        first_input = false;
    }

    camera.rotate(
        @as(f32, @floatCast(xpos - prev_xpos)) * sensitivity,
        @as(f32, @floatCast(ypos - prev_ypos)) * sensitivity,
    );

    prev_xpos = xpos;
    prev_ypos = ypos;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer if (gpa.deinit() == .leak) {
        debug.err("GPA detected memory leaks when deinit-ing.", .{});
    };

    try engine.init(gpa.allocator(), 800, 460, "Hello World");
    defer engine.deinit();

    // Init Renderers
    var quad_renderer = try engine.QuadRenderer.init(@embedFile("shader/quad_vert.glsl"), @embedFile("shader/quad_frag.glsl"));
    defer quad_renderer.deinit();

    compute_program = try engine.ComputeProgram.init(@embedFile("shader/compute.glsl"));
    defer compute_program.deinit();

    const out_unit = gl.TEXTURE0;

    output_texture = engine.Texture.init(out_unit, engine.window.width, engine.window.height, .{});
    output_texture.empty(0);
    output_texture.bind(0, gl.READ_WRITE);

    try engine.registerSizeCallback(resizeOutputTexture);

    quad_renderer.program.use();
    const output_texture_uniform = try quad_renderer.program.registerUniform("tex", .{ .owned = engine.Texture.apply });
    quad_renderer.program.applyOwnedUniform(output_texture_uniform, &output_texture);

    // Init World
    const world_size: u32 = 4;
    const world_root = -@as(i32, @intCast(world_size)) / 2;
    const Tree = voxel.KDTree(2);
    var world: Tree = try Tree.init(gpa.allocator(), m.ivec3(world_root, world_root, world_root), world_size);
    defer world.deinit();

    for (0..world_size) |x| {
        for (0..world_size) |y| {
            for (0..world_size) |z| {
                const voxel_pos = m.ivec3(world_root + @as(i32, @intCast(x)), world_root + @as(i32, @intCast(y)), world_root + @as(i32, @intCast(z)));

                if (@mod(x + y + z, 2) == 0) {
                    try world.add(voxel_pos, voxel.Voxel.init(
                        @intCast(x * @divFloor(256, world_size)),
                        @intCast(y * @divFloor(256, world_size)),
                        @intCast(z * @divFloor(256, world_size)),
                    ));
                }
            }
        }
    }
    
    // try world.add(m.ivec3(-2, -2, -2), voxel.Voxel.init(0, 0, 255));
    // try world.add(m.ivec3(-1, -1, -1), voxel.Voxel.init(0, 255, 0));
    // try world.add(m.ivec3(0, 0, 0), voxel.Voxel.init(255, 255, 255));
    // try world.add(m.ivec3(1, 1, 1), voxel.Voxel.init(255, 0, 0));

    debug.log("{any}", .{world.get(m.ivec3(0, 0, 0))});
    debug.log("{any}", .{@as(u32, @bitCast(try world.get(m.ivec3(0, 0, 0))))});

    const world_ssbo = engine.SSBO.init(u32, world.store.items);
    compute_program.use();
    world_ssbo.bind(0);

    // Init Player Camera
    camera = Camera.init(m.vec3(0, 0, -@as(f32, @floatFromInt(world_size))), .{});
    try camera.registerUniforms(engine.ComputeProgram, &compute_program);
    camera.applyUniforms(engine.ComputeProgram, &compute_program);

    try engine.registerSizeCallback(updateCamera);

    engine.glfwSetCursorPosCallback(cursorCallback);

    var frame_timer = try std.time.Timer.start();
    var debug_info_timer = try std.time.Timer.start();
    var frame_count: u32 = 0;

    var f11_down: bool = false;

    while (!engine.window.shouldClose()) {
        const delta_time: f32 = @as(f32, @floatFromInt(frame_timer.lap())) / 1e9;

        if (engine.window.keyPressed(glfw.KeyEscape)) {
            engine.window.close();
        }

        camera.tick(delta_time);

        camera.applyUniforms(engine.ComputeProgram, &compute_program);
        compute_program.dispatch(@intCast(output_texture.width), @intCast(output_texture.height), 1);

        engine.clearViewport();

        quad_renderer.render();

        engine.finishRender();

        frame_count += 1;
        if (debug_info_timer.read() > 1e9) {
            debug.log("FPS: {}", .{frame_count});
            frame_count = 0;
            _ = debug_info_timer.lap();
        }

        if (engine.window.keyPressed(glfw.KeyF11)) {
            if (!f11_down) {
                engine.window.toggleFullScreen();
                f11_down = true;
            }
        } else {
            f11_down = false;
        }
    }
}
