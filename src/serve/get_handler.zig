const std = @import("std");
const Request = @import("request");

pub fn run(req : *Request) !void {
    std.debug.print("We're in the get handler...\n", .{});
    const dest = req.dest orelse {
        std.debug.print("We never parsed a destination?\n", .{});
        return;
    };
    std.debug.print("We are in the get handler, handling a GET of \"{s}\"\n", .{dest});
}
