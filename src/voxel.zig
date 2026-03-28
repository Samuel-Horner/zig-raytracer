const std = @import("std");

const debug = @import("debug.zig");

// Working with 16 bit voxels here, with 16 bit addresses into KDTree

const Voxel = packed struct {
    r: u4,
    g: u4,
    b: u4,
    flags: u2 = 0,
    transparency: u2 = 0b11,
};

const empty: Voxel = @bitCast(0);
const filled: Voxel = .{ .r = 15, .g = 15, .b = 15 };

pub fn KDTree(comptime divisions: usize) type {
    return struct {
        const child_count = divisions * divisions * divisions;

        const Node = packed struct {
            value: Voxel,
            children: [child_count]u16 = [_]u16{0} ** child_count,
        };

        const Root = packed struct {
            x: u32,
            y: u32,
            z: u32,
            depth: u16,
            children: [child_count]u16 = [_]u16{0} ** child_count,
        };

        allocator: std.mem.Allocator,
        store: std.ArrayList(u16) = .empty,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) KDTree {
            var self: Self = .{
                .allocator = allocator,
            };

            self.store.append(self.allocator, @bitCast(Root{
                .x = 0,
                .y = 0,
                .z = 0,
                .depth = 0,
            }));

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.store.deinit(self.allocator);
        }
    };
}
