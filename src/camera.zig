const std = @import("std");

const gl = @import("gl");
const glfw = @import("glfw");

const debug = @import("debug.zig");
const engine = @import("engine.zig");
const m = @import("math.zig");

pub const Camera = struct {
    pos: m.Vec3,

    pixel00_loc: m.Vec3,

    pixel_delta_u: m.Vec3,
    pixel_delta_v: m.Vec3,

    focal_length: f32,
    fov: f32,

    dir: m.Vec3,
    right: m.Vec3,
    up: m.Vec3,

    pitch: f32,
    yaw: f32,

    uniforms: [4]usize,

    pub fn init(pos: m.Vec3, opts: struct {
        focal_length: f32 = 1,
        fov: f32 = 90,
    }) Camera {
        var self: Camera = undefined;

        self.pos = pos;

        self.focal_length = opts.focal_length;
        self.fov = std.math.degreesToRadians(opts.fov);

        self.pitch = 0;
        self.yaw = 0;

        // Set up look vectors
        self.rotate(90, 0);

        self.update();

        return self;
    }

    pub fn rotate(self: *Camera, yaw: f32, pitch: f32) void {
        self.yaw += yaw;
        self.pitch = std.math.clamp(self.pitch + pitch, -89, 89);

        const yaw_radians = std.math.degreesToRadians(self.yaw);
        const pitch_radians = std.math.degreesToRadians(self.pitch);

        // From Learn OpenGL
        // TODO: replace this with a rotaion matrix (maybe switch to quaternions)
        self.dir.data[0] = std.math.cos(yaw_radians) * std.math.cos(pitch_radians);
        self.dir.data[1] = std.math.sin(pitch_radians);
        self.dir.data[2] = std.math.sin(yaw_radians) * std.math.cos(pitch_radians);

        self.dir = self.dir.norm();
        self.right = self.dir.crossLH(m.vec3(0, 1, 0)).norm();
        self.up = self.right.crossLH(self.dir).norm();

        self.update();
    }

    pub fn tick(self: *Camera, delta_time: f32) void {
        const forward = m.vec3(- self.dir.data[0], 0, - self.dir.data[2]).norm();
        var movement = m.vec3(0, 0, 0);
        var speed: f32 = 10.0;

        if (engine.window.keyPressed(glfw.KeyW)) {
            movement.addAssign(forward);
        }

        if (engine.window.keyPressed(glfw.KeyS)) {
            movement.subAssign(forward);
        }

        if (engine.window.keyPressed(glfw.KeyD)) {
            movement.addAssign(self.right);
        }

        if (engine.window.keyPressed(glfw.KeyA)) {
            movement.subAssign(self.right);
        }

        if (engine.window.keyPressed(glfw.KeySpace)) {
            movement.data[1] += 1;
        }

        if (engine.window.keyPressed(glfw.KeyLeftControl)) {
            movement.data[1] -= 1;
        }

        if (engine.window.keyPressed(glfw.KeyLeftShift)) {
            speed *= 5;
        }

        movement.scaleAssign(speed * delta_time);

        self.move(movement);
    }

    pub fn move(self: *Camera, offset: m.Vec3) void {
        self.pos.addAssign(offset);
        self.update();
    }

    pub fn update(self: *Camera) void {
        const h: f32 = std.math.tan(self.fov / 2.0);

        const viewport_height: f32 = 2 * h * self.focal_length;
        const viewport_width: f32 = viewport_height *
            (@as(f32, @floatFromInt(engine.window.width)) /
                @as(f32, @floatFromInt(engine.window.height)));

        const viewport_u = self.right.scale(viewport_width);
        const viewport_v = self.up.scale(-viewport_height);

        self.pixel_delta_u = viewport_u.scale(1 / @as(f32, @floatFromInt(engine.window.width)));
        self.pixel_delta_v = viewport_v.scale(1 / @as(f32, @floatFromInt(engine.window.height)));
        self.pixel00_loc = self.pos.sub(self.dir.scale(self.focal_length)).sub(viewport_u.scale(0.5)).sub(viewport_v.scale(0.5)).add(self.pixel_delta_u.add(self.pixel_delta_v).scale(0.5));
    }

    pub fn registerUniforms(self: *Camera, program_type: type, program: *program_type) !void {
        self.uniforms[0] = try program.registerUniform("cam_pos", .{ .owned = Camera.applyPositionUniform });
        self.uniforms[1] = try program.registerUniform("cam_pixel00_loc", .{ .owned = Camera.applyPixel00PositionUniform });
        self.uniforms[2] = try program.registerUniform("cam_pixel_delta_u", .{ .owned = Camera.applyPixelDeltaUUniform });
        self.uniforms[3] = try program.registerUniform("cam_pixel_delta_v", .{ .owned = Camera.applyPixelDeltaVUniform });
    }

    pub fn applyUniforms(self: *Camera, program_type: type, program: *program_type) void {
        program.use();
        for (self.uniforms) |uniform| {
            program.applyOwnedUniform(uniform, self);
        }
    }

    fn applyPositionUniform(_self: *anyopaque, location: c_int) void {
        const self: *Camera = @ptrCast(@alignCast(_self));
        gl.Uniform3fv(location, 1, @as([*]const [3]f32, @ptrCast(&self.pos.data)));
    }

    fn applyPixel00PositionUniform(_self: *anyopaque, location: c_int) void {
        const self: *Camera = @ptrCast(@alignCast(_self));
        gl.Uniform3fv(location, 1, @as([*]const [3]f32, @ptrCast(&self.pixel00_loc.data)));
    }

    fn applyPixelDeltaUUniform(_self: *anyopaque, location: c_int) void {
        const self: *Camera = @ptrCast(@alignCast(_self));
        gl.Uniform3fv(location, 1, @as([*]const [3]f32, @ptrCast(&self.pixel_delta_u.data)));
    }

    fn applyPixelDeltaVUniform(_self: *anyopaque, location: c_int) void {
        const self: *Camera = @ptrCast(@alignCast(_self));
        gl.Uniform3fv(location, 1, @as([*]const [3]f32, @ptrCast(&self.pixel_delta_v.data)));
    }
};
