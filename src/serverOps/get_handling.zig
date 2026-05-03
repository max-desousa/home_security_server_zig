const std = @import("std");
const ComplexStream = @import("complexStream");
const home_page = @import("home_page.zig");
const sysOps = @import("sysOps");
const html = @import("html.zig");

//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
pub fn generic_getter(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) void {
    _ = &allocator;

    std.log.debug("I'm in a getter right now...\n", .{});

    if (sysOps.request_is_directory(io, stream)) {
        html.generate_and_serve_directory_html(io, stream);
    }
    else {
        if (request_is_for_favicon(stream)) {
            std.log.debug("Handling a favicon request\n", .{});
            stream.request.respond(
                "",
                .{
                    .status = .no_content,
                }
            ) catch {
                @panic("TODO: What do I do when server fails to reject favicon");
            };
        }
        else {
            if (is_playlist_request(stream)) {
                const file = sysOps.generate_playlist_file(stream.header_target) catch return;
                defer file.close(io);
                html.serve_file_2(io, stream, file, "application/vnd.apple.mpegurl");
            }
        }
    }
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn request_is_for_favicon(stream : *ComplexStream) bool {
    _, const target = std.mem.cutLast(u8, stream.header_target, "/") orelse return false;
    return std.mem.eql(u8, target, "favicon.ico");
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn is_playlist_request(stream : *ComplexStream) bool {
    _, const potentential_playlist = std.mem.cutLast(u8, stream.header_target, "/") orelse return false;
    const start_count = std.mem.count(u8, potentential_playlist, "start");
    if (1 > start_count) return false;
    const end_count = std.mem.count(u8, potentential_playlist, "end");
    if (1 > end_count) return false;
    std.log.debug("The request from target \"{s}\" IS a playlist request\n", .{ stream.header_target });
    return true;
}
