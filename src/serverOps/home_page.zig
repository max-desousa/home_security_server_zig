const std = @import("std");
const html = @import("html.zig");
const ComplexStream = @import("complexStream");

//******************************************************************************
// Function:
//
// Description: 
//******************************************************************************
pub fn serve(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) void {
    failable_serve_home_page(io, allocator, stream) catch {
        @panic("need to create failure upload path");
    };
}


//******************************************************************************
// Function:
//
// Description: 
//******************************************************************************
fn failable_serve_home_page(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) !void {
    const static_home_exists = blk: {
        _ = std.Io.Dir.statFile(.cwd(), io, "static/HelloWorld.html", .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (static_home_exists) {
        try html.serve(io, allocator, stream, "static/HelloWorld.html");
    }
    else {
        try generate_temporary_home_page(io, allocator);
        try html.serve(io, allocator, stream, ".generated/HelloWorld.html");
        std.Io.Dir.deleteFile(.cwd(), io, ".generated/HelloWorld.html") catch {};
    }
}


//******************************************************************************
// Function:
//
// Description: 
//******************************************************************************
fn generate_temporary_home_page(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    _ = &io;
    _ = &allocator;
}
