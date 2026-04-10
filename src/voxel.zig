const std = @import("std");

const m = @import("math.zig");
const debug = @import("debug.zig");

pub const Voxel = packed struct {
    r: u8,
    g: u8,
    b: u8,
    occupied: u1 = 1,
    flags: u7 = 0,

    pub fn init(r: u8, g: u8, b: u8) Voxel {
        return .{ .r = r, .g = g, .b = b };
    }
};

pub const empty: Voxel = @bitCast(@as(u32, 0));
pub const filled: Voxel = .{ .r = 255, .g = 255, .b = 255 };

pub fn KDTree(comptime divisions: u32) type {
    return struct {
        const child_count = divisions * divisions * divisions;
        const empty_children = [_]u32{0} ** child_count;

        const Node = packed struct {
            size: u32,
            value: Voxel = empty,
        };

        const MetaData = packed struct {
            x: i32,
            y: i32,
            z: i32,
            size: u32,

            fn getPos(self: *MetaData) m.iVec3 {
                return m.ivec3(self.x, self.y, self.z);
            }
        };

        const meta_data_size: u32 = @bitSizeOf(MetaData) / 32;
        const node_size: u32 = @bitSizeOf(Node) / 32;

        const Self = @This();

        allocator: std.mem.Allocator,
        store: std.ArrayList(u32) = .empty,

        pub fn init(allocator: std.mem.Allocator, pos: m.iVec3, size: u32) !Self {
            var self: Self = .{
                .allocator = allocator,
            };

            try self.store.appendSlice(self.allocator, @as([meta_data_size]u32, @bitCast(MetaData{
                .x = pos.data[0],
                .y = pos.data[1],
                .z = pos.data[2],
                .size = size,
            }))[0..]);

            _ = try self.addNode(size);

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.store.deinit(self.allocator);
        }

        fn getIndex(pos: m.iVec3) u32 {
            return @as(u32, @intCast(pos.data[0])) * divisions * divisions + @as(u32, @intCast(pos.data[1])) * divisions + @as(u32, @intCast(pos.data[2]));
        }

        fn getMetaData(self: *Self) *MetaData {
            return @alignCast(std.mem.bytesAsValue(MetaData, self.store.items[0..meta_data_size]));
        }

        fn addNode(self: *Self, size: u32) !u32 {
            const ptr: u32 = @intCast(self.store.items.len);
            try self.store.appendSlice(self.allocator, @as([node_size]u32, @bitCast(Node{ .size = size }))[0..]);
            try self.store.appendSlice(self.allocator, empty_children[0..]);
            return ptr;
        }

        fn getNodePtr(self: *Self, index: u32, children_ptr: u32) u32 {
            return self.store.items[children_ptr + index];
        }

        fn getOrAddNode(self: *Self, index: u32, children_ptr: u32, size: u32) !u32 {
            var ptr = self.getNodePtr(index, children_ptr);

            if (ptr == 0) { 
                ptr = try self.addNode(@divFloor(size, divisions));
                self.store.items[children_ptr + index] = ptr;
            }

            return ptr;
        }

        fn getRelativePos(abs_pos: m.iVec3, size: u32, voxel_pos: m.iVec3) m.iVec3 {
            const division_size: i32 = @intCast(@divFloor(size, divisions));
            const node_space_pos = voxel_pos.sub(abs_pos);

            return m.ivec3(
                @divFloor(node_space_pos.data[0], division_size),
                @divFloor(node_space_pos.data[1], division_size),
                @divFloor(node_space_pos.data[2], division_size),
            );
        }

        pub fn add(self: *Self, pos: m.iVec3, voxel: Voxel) !void {
            const meta_data = self.getMetaData();

            var size = meta_data.size;
            var node_pos = meta_data.getPos();
            var node_ptr = meta_data_size;

            while (size > 2) {
                const children_ptr = node_ptr + node_size;
                const relative_pos = getRelativePos(node_pos, size, pos);
                node_ptr = try self.getOrAddNode(getIndex(relative_pos), children_ptr, size);

                size = @divFloor(size, divisions);
                node_pos = node_pos.add(relative_pos.scale(@intCast(size)));
            }

            const chilren_ptr = node_ptr + node_size;
            const relative_pos = getRelativePos(node_pos, size, pos);

            self.store.items[chilren_ptr + getIndex(relative_pos)] = @bitCast(voxel);
        }

        pub fn get(self: *Self, pos: m.iVec3) !Voxel {
            const meta_data = self.getMetaData();

            var size = meta_data.size;
            var node_pos = meta_data.getPos();
            var node_ptr = meta_data_size;

            while (size > divisions) {
                const children_ptr = node_ptr + node_size;
                const relative_pos = getRelativePos(node_pos, size, pos);
                node_ptr = self.getNodePtr(getIndex(relative_pos), children_ptr);

                if (node_ptr == 0) return empty;

                size = @divFloor(size, divisions);
                node_pos = node_pos.add(relative_pos.scale(@intCast(size)));
            }

            const chilren_ptr = node_ptr + node_size;
            const relative_pos = getRelativePos(node_pos, size, pos);
            
            return std.mem.bytesToValue(Voxel, &self.store.items[chilren_ptr + getIndex(relative_pos)]);
        }
    };
}
