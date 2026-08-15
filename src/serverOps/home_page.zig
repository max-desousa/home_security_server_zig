const std = @import("std");
const html = @import("html.zig");
const ComplexStream = @import("complexStream");

//******************************************************************************
//* Function:    serve
//*
//* Description: This is a non-failing wrapper around
//               failable_serve_home_page so GET routing can call a void
//               function. Failures currently panic with a TODO rather than
//               changing the caller's return type.
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
//* Function:    failable_serve_home_page
//*
//* Description: This function prefers the checked-in static home page
//               (static/HelloWorld.html) when that file is present. If it
//               is missing, a temporary page is generated under
//               .generated/, served, and then deleted.
//
//               That fallback is how the home route stays usable even
//               without the static file on disk. The generate step is still
//               a stub, so the fallback path is not complete yet.
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
        try html.serve_file(io, stream, "static/HelloWorld.html");
    }
    else {
        try generate_temporary_home_page(io, allocator);
        try html.serve_file(io, stream, ".generated/HelloWorld.html");
        std.Io.Dir.deleteFile(.cwd(), io, ".generated/HelloWorld.html") catch {};
    }
}


//******************************************************************************
//* Function:    generate_temporary_home_page
//*
//* Description: This is intended to write the fallback home HTML used when
//               static/HelloWorld.html is not on disk. It is currently a
//               no-op stub - io and allocator are discarded - so the
//               generate-and-serve fallback in failable_serve_home_page
//               cannot succeed until this is filled in.
//******************************************************************************
fn generate_temporary_home_page(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    _ = &io;
    _ = &allocator;
}
