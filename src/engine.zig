const gl = @import("gl");
const glfw = @import("glfw");

const std = @import("std");

const debug = @import("debug.zig");

pub const Window = struct {
    id: *glfw.Window,
    width: c_int,
    height: c_int,
    name: [*:0]const u8,

    fn init(width: c_int, height: c_int, name: [*:0]const u8) !Window {
        return .{
            .id = try glfw.createWindow(width, height, name, null, null),
            .width = width,
            .height = height,
            .name = name,
        };
    }

    fn makeCurrent(self: *Window) void {
        glfw.makeContextCurrent(self.id);
    }

    fn deinit(self: *Window) void {
        glfw.destroyWindow(self.id);
    }
};

var engine_allocator: std.mem.Allocator = undefined;

const SizeCallback = *const fn(c_int, c_int) void;
var size_callbacks: std.ArrayList(SizeCallback) = .empty;

pub fn registerSizeCallback(callback: SizeCallback) !void {
    size_callbacks.append(engine_allocator, callback);
    debug.log("Registered new frame buffer size callback.", .{});
}

pub var window: Window = undefined;

fn glfwGlobalFrameBufferSizeCallback(_: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    window.width = width;
    window.height = height;
    gl.Viewport(0, 0, width, height);
    debug.log("Window resized to {}x{}.", .{ width, height });

    for (size_callbacks.items) |callback| {
        callback(width, height);
    }
}

var procs: gl.ProcTable = undefined;

pub fn init(allocator: std.mem.Allocator, window_width: c_int, window_height: c_int, name: [*:0]const u8) !void {
    engine_allocator = allocator;

    // Init GLFW
    try glfw.init();
    debug.log("Initialised GLFW {s}", .{glfw.getVersionString()});

    // Create Window
    window = try Window.init(window_width, window_height, name);
    window.makeCurrent();

    _ = glfw.setFramebufferSizeCallback(window.id, glfwGlobalFrameBufferSizeCallback);

    // Bind GL Procs
    if (!procs.init(glfw.getProcAddress)) return error.InitError;
    gl.makeProcTableCurrent(&procs);

    // Issue GL Configurations
    gl.ClearColor(1, 1, 1, 1);
}

pub fn deinit() void {
    gl.makeProcTableCurrent(null);

    glfw.makeContextCurrent(null);
    window.deinit();

    glfw.terminate();
}

pub fn render() void {
    while (!glfw.windowShouldClose(window.id)) {
        if (glfw.getKey(window.id, glfw.KeyEscape) == glfw.Press) {
            glfw.setWindowShouldClose(window.id, true);
        }

        gl.Clear(gl.COLOR_BUFFER_BIT);

        glfw.pollEvents();
        glfw.swapBuffers(window.id);
    }
}
