pub const zm = @import("zm");

pub const Vec3 = zm.Vec3f;
pub const vec = zm.vec;

pub fn vec3(x: f32, y: f32, z: f32) zm.Vec3f {
    return zm.Vec3f{ .data = .{ x, y, z } };
}
