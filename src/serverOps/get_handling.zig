const std = @import("std");
const ComplexStream = @import("complexStream");
const home_page = @import("home_page.zig");
const sysOps = @import("sysOps");
const html = @import("html.zig");

pub fn generic_getter(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) void {
    std.log.debug("I'm in a getter right now...\n", .{});

    if (sysOps.request_is_directory(stream.header_target)) {
        html.generate_and_serve_directory_html();
    }
    else {
        @panic("Todo - what should happen if user selects a file?");
    }

    if (std.mem.eql(u8, stream.header_target, "/")) {
        home_page.serve(io, allocator, stream);
    }
    else {
    }
}


