const std = @import("std");

pub fn generic_getter() void {
    std.debug.print("I'm in a getter right now...\n", .{});
}
