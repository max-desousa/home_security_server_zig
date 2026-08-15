//! POST target routing.
//!
//! Asks each feature file "is this yours?" and hands off. This file does
//! not parse bodies or write files.

const std = @import("std");
const ComplexStream = @import("complexStream");
const login = @import("login.zig");
const archive = @import("archive.zig");


//##############################################################################
// Function:    generic_poster
//
// Description: This is the POST router. Targets under /archival/ are treated
//              as video uploads and handed to archive_payload. /login is
//              handed to login.manage_attempt. Anything else is logged and
//              ignored so an unexpected POST does not get a half-handled
//              write.
//##############################################################################
pub fn generic_poster(
    allocator : std.mem.Allocator,
    io : std.Io,
    stream : *ComplexStream
) void {
    std.debug.print("I'm in a poster right now...\n", .{});
    std.log.debug("My header_target at start of poster is: {s}\n", .{stream.header_target});
    if (archive.is_archival_request(stream)) {
        std.log.debug("Post request IS video archival\n", .{});
        archive.archive_payload(allocator, io, stream);
    }
    else if (login.is_login_request(stream)) {
        login.manage_attempt(io, allocator, stream);
    }
    else {
        std.log.debug("Post request is something other than a video archival\n", .{});
        std.log.debug("\tHeader target is {s}\n", .{ stream.header_target });
    }
}
