const std = @import("std");

const engine = @import("engine.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer if (gpa.deinit() == .leak) {
        debug.err("GPA detected memory leaks when deinit-ing.", .{});
    };

    try engine.init(gpa.allocator(), 800, 460, "Hello World");
    defer engine.deinit();

    engine.render();
}
