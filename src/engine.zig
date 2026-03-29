const std = @import("std");

const gl = @import("gl");
const glfw = @import("glfw");

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

    fn makeCurrent(self: *const Window) void {
        glfw.makeContextCurrent(self.id);
    }

    fn deinit(self: *Window) void {
        glfw.destroyWindow(self.id);
    }

    pub fn shouldClose(self: *const Window) bool {
        return glfw.windowShouldClose(self.id);
    }

    pub fn keyPressed(self: *const Window, key: c_int) bool {
        return glfw.getKey(self.id, key) == glfw.Press;
    }

    pub fn close(self: *const Window) void {
        glfw.setWindowShouldClose(self.id, true);
    }
};

// Allows for uniform function declaration with struct ownership.
pub const UniformFunction = union {
    basic: *const fn (c_int) void,
    owned: *const fn (*anyopaque, c_int) void,
};

pub const Uniform = struct {
    location: c_int,
    function: ?UniformFunction,

    fn applyOwned(self: *const Uniform, owner: *anyopaque) void {
        self.function.?.owned(owner, self.location);
    }

    fn apply(self: *const Uniform) void {
        self.function.?.basic(self.location);
    }

    fn init(location: c_int, function: ?UniformFunction) Uniform {
        return Uniform{ .location = location, .function = function };
    }
};

fn compileShader(shader: c_uint, source: []const u8) !void {
    gl.ShaderSource(shader, 1, &.{source.ptr}, &.{@intCast(source.len)});
    gl.CompileShader(shader);

    var success: i32 = undefined;
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, (&success)[0..1]);
    if (success != 1) {
        var info_log: [512:0]u8 = undefined;
        gl.GetShaderInfoLog(shader, info_log.len, null, &info_log);
        debug.err("Shader {} failed to compile.\n{s}", .{ shader, std.mem.sliceTo(&info_log, 0) });

        return error.ShaderCompilationFailed;
    }
}

pub const Texture = struct {
    const TextureOpts = struct {
        internal_format: u32 = gl.RGBA32F,
        format: u32 = gl.RGBA,
        type: u32 = gl.FLOAT,
    };

    id: c_uint,
    unit: u32,

    width: c_int,
    height: c_int,

    opts: TextureOpts,

    pub fn init(comptime unit: comptime_int, width: c_int, height: c_int, opts: TextureOpts) Texture {
        var texture: Texture = undefined;

        texture.unit = unit;

        texture.width = width;
        texture.height = height;

        texture.opts = opts;

        gl.GenTextures(1, (&texture.id)[0..1]);
        texture.activate();
        gl.BindTexture(gl.TEXTURE_2D, texture.id);

        // Basic Texture Parameters
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);

        return texture;
    }

    pub fn empty(self: *Texture, level: c_int) void {
        gl.TexImage2D(gl.TEXTURE_2D, level, @intCast(self.opts.internal_format), self.width, self.height, 0, self.opts.format, self.opts.type, null);
    }

    pub fn bind(self: *Texture, level: c_int, comptime mode: comptime_int) void {
        gl.BindImageTexture(self.unit - gl.TEXTURE0, self.id, level, gl.FALSE, 0, mode, self.opts.internal_format);
    }

    pub fn activate(self: *Texture) void {
        gl.ActiveTexture(self.unit);
    }

    pub fn apply(self: *anyopaque, location: c_int) void {
        const self_ptr: *Texture = @ptrCast(@alignCast(self));
        gl.Uniform1i(location, @intCast(self_ptr.unit - gl.TEXTURE0));
    }

    pub fn resize(self: *Texture, level: c_int, width: c_int, height: c_int) void {
        self.width = width;
        self.height = height;

        self.empty(level);
    }
};

pub const SSBO = struct {
    ssbo: c_uint,
    length: usize,

    pub fn bind(ssbo: *const SSBO, bind_point: c_uint) void {
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, bind_point, ssbo.ssbo);
    }

    pub fn init(comptime value_type: type, values: []value_type) SSBO {
        var ssbo: SSBO = undefined;

        gl.GenBuffers(1, (&ssbo.ssbo)[0..1]);
        gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, ssbo.ssbo);
        
        gl.BufferData(gl.SHADER_STORAGE_BUFFER, @intCast(values.len * @sizeOf(value_type)), values.ptr, gl.STATIC_DRAW);

        ssbo.length = values.len;

        return ssbo;
    }
};

pub const ComputeProgram = struct {
    id: c_uint,
    uniforms: std.ArrayList(Uniform),

    fn linkProgram(self: *ComputeProgram, compute_shader: c_uint) !void {
        gl.AttachShader(self.id, compute_shader);

        gl.LinkProgram(self.id);

        // Check program link status
        var success: i32 = undefined;
        gl.GetProgramiv(self.id, gl.LINK_STATUS, (&success)[0..1]);
        if (success != 1) {
            var info_log: [512:0]u8 = undefined;
            gl.GetProgramInfoLog(self.id, info_log.len, null, &info_log);
            debug.err("Program {} failed to link.\n{s}", .{ self.id, std.mem.sliceTo(&info_log, 0) });

            return error.ProgramLinkFailed;
        }
    }

    pub fn init(compute_source: []const u8) !ComputeProgram {
        var compute_program: ComputeProgram = undefined;

        const compute_shader: c_uint = gl.CreateShader(gl.COMPUTE_SHADER);
        try compileShader(compute_shader, compute_source);

        compute_program.id = gl.CreateProgram();
        try compute_program.linkProgram(compute_shader);

        debug.log("Created compute program {}.", .{compute_program.id});

        gl.DeleteShader(compute_shader);

        compute_program.uniforms = .empty;

        return compute_program;
    }

    pub fn deinit(self: *ComputeProgram) void {
        self.uniforms.deinit(engine_allocator);
    }

    pub fn use(self: *ComputeProgram) void {
        gl.UseProgram(self.id);
    }

    pub fn dispatch(self: *ComputeProgram, x: u32, y: u32, z: u32) void {
        gl.UseProgram(self.id);

        gl.DispatchCompute(x, y, z);

        gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT);
    }

    pub fn registerUniform(self: *ComputeProgram, comptime name: [:0]const u8, function: UniformFunction) !usize {
        const location = gl.GetUniformLocation(self.id, name.ptr);

        if (location == -1) {
            debug.err("Failed to find uniform \"{s}\" in program {}.", .{ name, self.id });
            return error.UniformNotFound;
        }

        try self.uniforms.append(engine_allocator, Uniform.init(location, function));

        return self.uniforms.items.len - 1;
    }

    pub fn applyAllUniforms(self: *ComputeProgram) void {
        for (self.uniforms.items) |uniform| {
            uniform.apply();
        }
    }

    pub fn applyUniform(self: *ComputeProgram, uniform: usize) void {
        self.uniforms.items[uniform].apply();
    }

    pub fn applyOwnedUniform(self: *ComputeProgram, uniform: usize, owner: *anyopaque) void {
        self.uniforms.items[uniform].applyOwned(owner);
    }
};

// Simple Vertex + Fragment Program
pub const Program = struct {
    id: c_uint,
    uniforms: std.ArrayList(Uniform),

    fn linkProgram(self: *Program, vertex_shader: c_uint, fragment_shader: c_uint) !void {
        gl.AttachShader(self.id, vertex_shader);
        gl.AttachShader(self.id, fragment_shader);

        gl.LinkProgram(self.id);

        // Check program link status
        var success: i32 = undefined;
        gl.GetProgramiv(self.id, gl.LINK_STATUS, (&success)[0..1]);
        if (success != 1) {
            var info_log: [512:0]u8 = undefined;
            gl.GetProgramInfoLog(self.id, info_log.len, null, &info_log);
            debug.err("Program {} failed to link.\n{s}", .{ self.id, std.mem.sliceTo(&info_log, 0) });

            return error.ProgramLinkFailed;
        }
    }

    pub fn init(vertex_source: []const u8, fragment_source: []const u8) !Program {
        var program: Program = undefined;

        // Vertex Shader
        const vertex_shader: c_uint = gl.CreateShader(gl.VERTEX_SHADER);
        try compileShader(vertex_shader, vertex_source);

        // Fragment Shader
        const fragment_shader: c_uint = gl.CreateShader(gl.FRAGMENT_SHADER);
        try compileShader(fragment_shader, fragment_source);

        // Create and link program
        program.id = gl.CreateProgram();
        try program.linkProgram(vertex_shader, fragment_shader);

        debug.log("Created program {}.", .{program.id});

        // Delete shaders
        gl.DeleteShader(vertex_shader);
        gl.DeleteShader(fragment_shader);

        // Setup Uniform List
        program.uniforms = .empty;

        return program;
    }

    pub fn registerUniform(self: *Program, comptime name: [:0]const u8, function: UniformFunction) !usize {
        const location = gl.GetUniformLocation(self.id, name.ptr);

        if (location == -1) {
            debug.err("Failed to find uniform \"{s}\" in program {}.", .{ name, self.id });
            return error.UniformNotFound;
        }

        try self.uniforms.append(engine_allocator, Uniform.init(location, function));

        return self.uniforms.items.len - 1;
    }

    pub fn use(self: *Program) void {
        gl.UseProgram(self.id);
    }

    pub fn applyAllUniforms(self: *Program) void {
        for (self.uniforms.items) |uniform| {
            uniform.apply();
        }
    }

    pub fn applyUniform(self: *Program, uniform: usize) void {
        self.uniforms.items[uniform].apply();
    }

    pub fn applyOwnedUniform(self: *Program, uniform: usize, owner: *anyopaque) void {
        self.uniforms.items[uniform].applyOwned(owner);
    }

    pub fn deinit(self: *Program) void {
        self.uniforms.deinit(engine_allocator);
    }
};

pub const QuadRenderer = struct {
    const verts: [24]f32 = .{
        -1, 1,  0, 0,
        -1, -1, 0, 1,
        1,  -1, 1, 1,
        -1, 1,  0, 0,
        1,  -1, 1, 1,
        1,  1,  1, 0,
    };

    program: Program,

    vao: c_uint,
    vbo: c_uint,

    pub fn init(vertex_source: []const u8, fragment_source: []const u8) !QuadRenderer {
        var quad_renderer: QuadRenderer = undefined;

        quad_renderer.program = try Program.init(vertex_source, fragment_source);

        gl.GenVertexArrays(1, (&quad_renderer.vao)[0..1]);
        gl.GenBuffers(1, (&quad_renderer.vbo)[0..1]);

        gl.BindVertexArray(quad_renderer.vao);
        gl.BindBuffer(gl.ARRAY_BUFFER, quad_renderer.vao);

        gl.BufferData(gl.ARRAY_BUFFER, @intCast(@sizeOf(f32) * QuadRenderer.verts.len), &QuadRenderer.verts, gl.STATIC_DRAW);

        gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
        gl.EnableVertexAttribArray(0);

        return quad_renderer;
    }

    pub fn deinit(self: *QuadRenderer) void {
        self.program.deinit();
    }

    pub fn render(self: *QuadRenderer) void {
        self.program.use();

        gl.BindVertexArray(self.vao);
        gl.DrawArrays(gl.TRIANGLES, 0, 6);
    }
};

var engine_allocator: std.mem.Allocator = undefined;

const SizeCallback = *const fn (c_int, c_int) void;
var size_callbacks: std.ArrayList(SizeCallback) = .empty;

pub fn registerSizeCallback(callback: SizeCallback) !void {
    try size_callbacks.append(engine_allocator, callback);
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

pub fn glfwSetCursorPosCallback(callback: *const fn (*c_long, f64, f64) callconv(.c) void) void {
    _ = glfw.setCursorPosCallback(window.id, callback);
}

var procs: gl.ProcTable = undefined;

pub fn init(allocator: std.mem.Allocator, window_width: c_int, window_height: c_int, name: [*:0]const u8) !void {
    engine_allocator = allocator;

    // Init GLFW
    try glfw.init();
    debug.log("Initialised GLFW {s}", .{glfw.getVersionString()});

    // Window Hints
    glfw.windowHint(glfw.ContextVersionMajor, 4);
    glfw.windowHint(glfw.ContextVersionMinor, 6);

    // Create Window
    window = try Window.init(window_width, window_height, name);
    window.makeCurrent();

    _ = glfw.setFramebufferSizeCallback(window.id, glfwGlobalFrameBufferSizeCallback);

    glfw.setInputMode(window.id, glfw.Cursor, glfw.CursorDisabled);

    // Bind GL Procs
    if (!procs.init(glfw.getProcAddress)) return error.InitError;
    gl.makeProcTableCurrent(&procs);
    debug.log("Loaded OpenGL {s} {}.{}.", .{ @tagName(gl.info.profile orelse "unkown"), gl.info.version_major, gl.info.version_minor });

    // Issue GL Configurations
    gl.ClearColor(1, 0, 1, 1);
}

pub fn deinit() void {
    gl.makeProcTableCurrent(null);

    glfw.makeContextCurrent(null);
    window.deinit();

    size_callbacks.deinit(engine_allocator);

    glfw.terminate();
}

pub fn clearViewport() void {
    gl.Clear(gl.COLOR_BUFFER_BIT);
}

pub fn finishRender() void {
    glfw.pollEvents();
    glfw.swapBuffers(window.id);
}
