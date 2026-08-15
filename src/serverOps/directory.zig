//! GET directory listing.
//!
//! Locks a temp HTML file, asks `sysOps` to fill the folder-browser view,
//! then sends it through `respond`. `get.zig` asks `is_directory_request`
//! during classify; it does not generate or send the listing itself.

const std = @import("std");
const ComplexStream = @import("complexStream");
const sysOps = @import("sysOps");
const respond = @import("respond.zig");

const HTML_FILE_TO_SERVE = ".html_to_serve.html";


//******************************************************************************
//* Function:    is_directory_request
//*
//* Description: Wrapper around sysOps.request_is_directory so GET classify
//               can ask this file "is this yours?" without importing sysOps.
//******************************************************************************
pub fn is_directory_request(io : std.Io, stream : *ComplexStream) bool {
    return sysOps.request_is_directory(io, stream);
}


//******************************************************************************
//* Function:    generate_and_serve_directory_html
//*
//* Description: This function creates a locked temporary HTML file, asks
//               sysOps.generate_html_for_folder to fill it with the
//               directory-browser view, serves that file, then deletes the
//               temp. The exclusive lock is there so two overlapping
//               directory requests do not stomp the same backing file.
//
//               Any failure to lock or generate becomes send_error_state
//               instead of crashing the thread.
//******************************************************************************
pub fn generate_and_serve_directory_html(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream
) void {
    //Try creating file to generate html into if failure - respond negative response
    var file = std.Io.Dir.createFile(
        .cwd(),
        io,
        HTML_FILE_TO_SERVE,
        .{
            .read = true,
            .lock = .exclusive,
        }
    ) catch {
        respond.send_error_state(stream, "Backing file could not be secured");
        return;
    };
    defer std.Io.Dir.deleteFile(.cwd(), io, HTML_FILE_TO_SERVE) catch |err| {
        std.log.err("Could not delete the temporary file used for html view of directory due to error: {any}", .{ err });
    };
    defer file.close(io);

    sysOps.generate_html_for_folder(io, allocator, &file, stream.fs_adjusted_target) catch |err| {
        std.log.err("Failed dir html generation due to error {any}\n", .{ err });
        respond.send_error_state(stream, "Error generating your view of the directory");
    };

    respond.serve_file(io, stream, &file, "text/html; charset=utf-8");
}
