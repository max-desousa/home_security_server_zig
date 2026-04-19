const std = @import("std");
const ComplexStream = @import("complexStream");
const home_page = @import("home_page.zig");

pub fn generic_getter(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) void {
    std.log.debug("I'm in a getter right now...\n", .{});

    if (std.mem.eql(u8, stream.header_target, "/")) {
        home_page.serve(io, allocator, stream);
    }
    else {
    }
}


