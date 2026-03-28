const std = @import("std");

const gl = @import("gl");
const glfw = @import("glfw");

const engine = @import("engine.zig");
const debug = @import("debug.zig");

var output_texture: engine.Texture = undefined;

fn resizeOutputTexture(width: c_int, height: c_int) void {
    output_texture.resize(0, width, height);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer if (gpa.deinit() == .leak) {
        debug.err("GPA detected memory leaks when deinit-ing.", .{});
    };

    try engine.init(gpa.allocator(), 800, 460, "Hello World");
    defer engine.deinit();

    var quad_renderer = try engine.QuadRenderer.init(@embedFile("shader/quad_vert.glsl"), @embedFile("shader/quad_frag.glsl"));
    defer quad_renderer.deinit();

    var compute_program = try engine.ComputeProgram.init(@embedFile("shader/compute.glsl"));
    defer compute_program.deinit();

    const out_unit = gl.TEXTURE0;

    output_texture = engine.Texture.init(out_unit, engine.window.width, engine.window.height, .{});
    output_texture.empty(0);
    output_texture.bind(0, gl.READ_WRITE);

    try engine.registerSizeCallback(resizeOutputTexture);

    quad_renderer.program.use();
    const output_texture_uniform = try quad_renderer.program.registerUniform("tex", .{ .owned = engine.Texture.apply });
    quad_renderer.program.applyOwnedUniform(output_texture_uniform, &output_texture);

    while (!engine.window.shouldClose()) {
        if (engine.window.keyPressed(glfw.KeyEscape)) {
            engine.window.close();
        }

        engine.clearViewport();

        compute_program.dispatch(@intCast(output_texture.width), @intCast(output_texture.height), 1);

        quad_renderer.render();

        engine.finishRender();
    }
}
