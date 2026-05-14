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
                var file = sysOps.generate_and_get_playlist_file(
                    io, 
                    allocator, 
                    stream.header_target
                ) catch |err| {
                    std.log.err("Encountered error creating playlist file: {any}\n", .{ err });
                    return;
                };
                defer file.close(io);
                //stream.request.respond(
                //    "",
                //    .{
                //        .status = .no_content,
                //    }
                //) catch {
                //    @panic("TODO: What do I do when server fails to reject favicon");
                //};
                html.serve_file_2(io, stream, &file, "application/vnd.apple.mpegurl");
            }
            else if (is_video_file_request(stream)) {
                std.log.info("Got video request: {s}\n", .{ stream.header_target });
                html.serve_file_from_path(
                    io,
                    stream,
                    stream.header_target,
                     //"application/vnd.apple.mpegurl",
                     "video/mp2t",
                );
            }
            else {
                std.log.err("Unexpected request type through target: {s}\n", .{ stream.header_target });
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


//******************************************************************************
//* Function: 
//* 
//* Description: 
//******************************************************************************
fn is_video_file_request(stream : *ComplexStream) bool {
    const video_file_extensions = [_][]const u8{
        ".ts",
        ".mov",
        ".mp4",
        ".avi",
        ".mpeg",
    };
    for (video_file_extensions) |extension| {
        const ext_len = extension.len;
        if(std.mem.eql(
            u8,
            stream.header_target[(stream.header_target.len - ext_len)..stream.header_target.len],
            extension)
        ) {
            return true;
        }
    }
    return false;
}
