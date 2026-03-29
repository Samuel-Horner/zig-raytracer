const std = @import("std");

const m = @import("math.zig");
const debug = @import("debug.zig");

// Working with 16 bit voxels here, with 16 bit addresses into KDTree

const Voxel = packed struct {
    r: u4,
    g: u4,
    b: u4,
    flags: u2 = 0,
    transparency: u2 = 0b11,
};

pub const empty: Voxel = .{ .r = 0, .g = 0, .b = 0, .flags = 0, .transparency = 0 };
pub const filled: Voxel = .{ .r = 15, .g = 15, .b = 15 };

pub fn KDTree(comptime divisions: usize) !type {
    if (!(divisions > 0 and (divisions & (divisions - 1)) == 0)) {
        return error.InvalidDivisions;
    }

    return struct {
        const child_count = divisions * divisions * divisions;

        const Children = [child_count]u16;
        const empty_children = [_]u16{@as(u16, @bitCast(empty))} ** child_count;

        const Node = packed struct {
            value: Voxel = empty,
        };

        const node_size = @bitSizeOf(Node) / 16;

        const Root = packed struct {
            x: i32,
            y: i32,
            z: i32,
            depth: u16,
            size: u32,
        };

        const root_size = @bitSizeOf(Root) / 16;

        allocator: std.mem.Allocator,
        store: std.ArrayList(u16) = .empty,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, root_pos: m.iVec3, size: u32) !Self {
            var self: Self = .{
                .allocator = allocator,
            };

            var max_depth: u16 = 0;
            const inc: u5 = @intCast(std.math.log2(divisions));
            var i = size >> inc;
            while (i > 0) {
                max_depth += 1;
                i >>= inc;
            }

            try self.store.appendSlice(self.allocator, @as([root_size]u16, @bitCast(Root{
                .x = root_pos.data[0],
                .y = root_pos.data[1],
                .z = root_pos.data[2],
                .size = size,
                .depth = max_depth,
            }))[0..]);

            try self.store.appendSlice(self.allocator, empty_children[0..]);

            return self;
        }

        fn getIndex(pos: m.iVec3) usize {
            return @as(usize, @intCast(pos.data[0])) * divisions * divisions + @as(usize, @intCast(pos.data[1])) * divisions + @as(usize, @intCast(pos.data[2]));
        }

        fn getRoot(self: *Self) *Root {
            return @alignCast(std.mem.bytesAsValue(Root, self.store.items[0..root_size]));
        }

        fn getNode(self: *Self, ptr: u16) *Node {
            return @alignCast(std.mem.bytesAsValue(Node, self.store.items[ptr .. ptr + node_size]));
        }

        fn getNodePtr(self: *Self, index: usize, children_start: usize) u16 {
            const children = self.store.items[children_start .. children_start + child_count];
            return children[index];
        }

        fn addNode(self: *Self) !u16 {
            const ptr = self.store.items.len;
            try self.store.appendSlice(self.allocator, @as([node_size]u16, @bitCast(Node{}))[0..]);
            try self.store.appendSlice(self.allocator, empty_children[0..]);
            return @intCast(ptr);
        }

        fn addOrGetNodePtr(self: *Self, index: usize, children_start: usize) !u16 {
            var children = self.store.items[children_start .. children_start + child_count];
            var ptr = children[index];

            if (ptr == 0) {
                ptr = try self.addNode();
                children = self.store.items[children_start .. children_start + child_count];
                children[index] = ptr;
            }

            return ptr;
        }

        fn getChildPosition(node_pos: m.iVec3, size: u32, pos: m.iVec3) m.iVec3 {
            const relative_pos = pos.sub(node_pos);
            const scale: u5 = @intCast(std.math.log2(size / divisions));

            return m.ivec3(
                relative_pos.data[0] >> scale,
                relative_pos.data[1] >> scale,
                relative_pos.data[2] >> scale,
            );
        }

        pub fn add(self: *Self, pos: m.iVec3, voxel: Voxel) !void {
            const root = self.getRoot();
            var node_pos = m.ivec3(root.x, root.y, root.z);
            var children_start: usize = root_size;
            var size = root.size;
            const inc: u5 = @intCast(std.math.log2(divisions));

            for (0..root.depth) |_| {
                const child_pos = Self.getChildPosition(node_pos, size, pos);
                const ptr = try self.addOrGetNodePtr(Self.getIndex(child_pos), children_start);

                children_start = ptr + node_size;
                size >>= inc;

                node_pos = node_pos.add(child_pos.scale(divisions));
            }

            const relative_voxel_pos = pos.sub(node_pos);
            const index = Self.getIndex(relative_voxel_pos);

            const voxel_data: u16 = @bitCast(voxel);

            const children = self.store.items[children_start .. children_start + child_count];
            children[index] = voxel_data;
        }

        pub fn get(self: *Self, pos: m.iVec3) Voxel {
            const root = self.getRoot();
            var node_pos = m.ivec3(root.x, root.y, root.z);
            var children_start: usize = root_size;
            var size = root.size;
            const inc: u5 = @intCast(std.math.log2(divisions));

            for (0..root.depth) |_| {
                const child_pos = Self.getChildPosition(node_pos, size, pos);
                const ptr = self.getNodePtr(Self.getIndex(child_pos), children_start);

                if (ptr == 0) { return empty; }

                children_start = ptr + node_size;
                size >>= inc;

                node_pos = node_pos.add(child_pos.scale(divisions));
            }

            const relative_voxel_pos = pos.sub(node_pos);
            const index = Self.getIndex(relative_voxel_pos);

            const children = self.store.items[children_start .. children_start + child_count];
            return std.mem.bytesToValue(Voxel, &children[index]);
        }

        pub fn deinit(self: *Self) void {
            self.store.deinit(self.allocator);
        }
    };
}
