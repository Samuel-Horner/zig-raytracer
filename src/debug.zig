const std = @import("std");

// ##### Log Statements #####
pub fn log(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("[\x1b[32mLOG\x1b[0m] " ++ fmt ++ "\n", args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("[\x1b[31mERROR\x1b[0m] " ++ fmt ++ "\n", args);
}
