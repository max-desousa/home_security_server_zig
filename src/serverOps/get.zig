//! GET target routing.
//!
//! Classify `header_target` by asking each feature file "is this yours?",
//! then hand off. This file does not generate playlists, build directory
//! listings, or stream bytes.

const std = @import("std");
const ComplexStream = @import("complexStream");
const respond = @import("respond.zig");
const playlist = @import("playlist.zig");
const directory = @import("directory.zig");
const settings_dispatcher = @import("dispatch_settings.zig").dispatch_settings_request;


//Enum for routing table
const RequestType = enum {
    Directory,
    File_SendAsVideo,
    Home,
    Playlist_PlayerSetup,
    Playlist_StreamCalculated,
    Playlist_StreamSingleFile,
    Static,
    Settings,
};


//******************************************************************************
//* Function:    classify_request_type
//*
//* Description: This function turns header_target into a RequestType so
//               generic_getter can stay a thin switch. Order matters: home,
//               static HTML, directory, player setup, calculated playlist,
//               single-file playlist, then video file.
//
//               Returning null is deliberate. Unrecognized targets should
//               not guess a handler - the getter sends no-content instead
//               of leaving the client hanging or serving the wrong thing.
//******************************************************************************
fn classify_request_type(
    io : std.Io,
    stream : *ComplexStream,
) ?RequestType {
    //Is the request a home page?
    if (std.mem.eql(u8, stream.header_target, "/")) return .Home;

    // Is this request - in any way - related to settings?
    if (std.mem.startsWith(u8, stream.header_target, "/settings")) return .Settings;

    //Checking if the request is a static html file:
    var path_buffer : [1024]u8 = undefined;
    const path_string = std.fmt.bufPrint(&path_buffer, "static{s}.html", .{ stream.header_target }) catch {
        @panic("TODO: how do I want to handle buffer failures while looking for static html?");
    };
    const is_static : bool = blk: {
        std.debug.print("The path_string being evaluated is: \"{s}\"\n", .{ path_string });
        _ = std.Io.Dir.statFile(.cwd(), io, path_string, .{ .follow_symlinks = false }) catch {
            break :blk false;
        };
        break :blk true;
    };
    if (is_static) return .Static;

    if (directory.is_directory_request(io, stream)) return .Directory;

    if (playlist.is_player_setup_request(stream)) return .Playlist_PlayerSetup;

    if (playlist.is_calculated_request(stream)) return .Playlist_StreamCalculated;

    if (playlist.is_single_file_request(stream)) return .Playlist_StreamSingleFile;

    if (is_video_file_request(stream)) return .File_SendAsVideo; {
        std.log.info("Got video request: {s}\n", .{ stream.header_target });
    }

    ////Checking if the request is a file... if it is... what type of file
    ////request is it?
    //if (std.Io.Dir.statFile(.cwd(), io, stream.fs_adjusted_target, .{})) |stat| {
    //}

    return null;
}


//******************************************************************************
//* Function:    generic_getter
//*
//* Description: This is the GET router. It classifies the request, then
//               dispatches to the home, static, directory, playlist, or
//               video helpers. The rest of this function SHOULD stay
//               redirects to more appropriate function calls.
//
//               Unknown types get an empty 204 so the client is not left
//               spinning on a request we do not know how to serve.
//******************************************************************************
pub fn generic_getter(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) void {
    std.log.debug("I'm in a getter right now...\n", .{});

    //Simplify the request type for routing.
    //On the event that the type is invalid... send "no content" response to
    //the client
    const request_type : RequestType = classify_request_type(io, stream) orelse {
        respond.send_no_content(stream);
        return;
    };

    //This is the routing table. The rest of this function SHOULD be redirects
    //to more appropriate fucntion calls.
    switch (request_type) {
        .Home => {
            respond.serve_file_from_path(
                io,
                stream,
                "/static/HelloWorld.html",
                "text/html; charset=utf-8",
            );
        },
        .Settings => {
            settings_dispatcher(io, stream);
        },
        .Directory => directory.generate_and_serve_directory_html(io, allocator, stream),
        .Playlist_PlayerSetup => {
            respond.serve_file_from_path(
                io,
                stream,
                "/static/player.html",
                "text/html; charset=utf-8",
            );
        },
        .Playlist_StreamCalculated => playlist.generate_and_serve_playlist(io, allocator, stream),
        .File_SendAsVideo => {
            respond.serve_file_from_path(
                io,
                stream,
                stream.header_target,
                 //"application/vnd.apple.mpegurl",
                 "video/mp2t",
            );
        },
        .Playlist_StreamSingleFile => playlist.generate_and_serve_playlist(io, allocator, stream),
        .Static => {
            var path_buffer : [1024]u8 = undefined;
            const path_string = std.fmt.bufPrint(&path_buffer, "/static{s}.html", .{ stream.header_target }) catch |err| {
                std.debug.print("TODO: What do I want to do with an error in the buffer here\n", .{});
                std.debug.print("\tThe error for this instance was: {any}\n", .{ err });
                return;
            };
            respond.serve_file_from_path(
                io,
                stream,
                path_string,
                "text/html; charset=utf-8",
            );
        },
    }
}


//******************************************************************************
//* Function:    is_video_file_request
//*
//* Description: This function checks whether the request target ends in a
//               known video extension (.ts, .mov, .mp4, .avi, .mpeg). Those
//               GET targets should be served as video rather than as a
//               directory listing or a static HTML page.
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
