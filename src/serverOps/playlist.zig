//! HLS playlist URLs and the file that gets served for them.
//!
//! This file owns the playlist URL shapes (`&player=true`, start/end
//! window, `?m3u8`) and the generate-and-serve path. `get.zig` asks
//! these predicates during classify, then calls
//! `generate_and_serve_playlist` for the two stream variants.

const std = @import("std");
const ComplexStream = @import("complexStream");
const sysOps = @import("sysOps");
const respond = @import("respond.zig");


//******************************************************************************
//* Function:    is_player_setup_request
//*
//* Description: True when the target asks for the HTML player page rather
//               than a playlist file. GET routing then serves
//               static/player.html.
//******************************************************************************
pub fn is_player_setup_request(stream : *ComplexStream) bool {
    return std.mem.endsWith(u8, stream.header_target, "&player=true");
}


//******************************************************************************
//* Function:    is_calculated_request
//*
//* Description: This is a heuristic for a calculated (time-range) playlist
//               URL. The last path segment has to contain both "start" and
//               "end" - that is the form the player uses when asking for a
//               window of archive clips rather than a single file.
//******************************************************************************
pub fn is_calculated_request(stream : *ComplexStream) bool {
    _, const potentential_playlist = std.mem.cutLast(u8, stream.header_target, "/") orelse return false;
    const start_count = std.mem.count(u8, potentential_playlist, "start");
    if (1 > start_count) return false;
    const end_count = std.mem.count(u8, potentential_playlist, "end");
    if (1 > end_count) return false;
    std.log.debug("The request from target \"{s}\" IS a playlist request\n", .{ stream.header_target });
    return true;
}


//******************************************************************************
//* Function:    is_single_file_request
//*
//* Description: True when the target is a single-file playlist (`?m3u8`).
//               GET routing uses the same generate-and-serve path as a
//               calculated window; sysOps decides how many clips to list.
//******************************************************************************
pub fn is_single_file_request(stream : *ComplexStream) bool {
    return std.mem.endsWith(u8, stream.header_target, "?m3u8");
}


//******************************************************************************
//* Function: generate_and_serve_playlist
//*
//* Description: Wrapper for a function that can fail to generate and serve
//*              playlist. This lets us use try, and in the event of a failure,
//*              we send and forget a page to the client with an error state so
//*              that they know what's happening.
//******************************************************************************
pub fn generate_and_serve_playlist(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) void {
    failable_generate_and_serve_playlist(io, allocator, stream) catch |err| {
        var backing_buffer_for_playlist_failure : [512]u8 = undefined;
        const error_msg = std.fmt.bufPrint(
            &backing_buffer_for_playlist_failure,
            "Could not generate/serve playlist file due to nested error: {any}",
            .{ err }
        ) catch return;
        respond.send_error_state(stream, error_msg);
    };
}

//******************************************************************************
//* Function:    failable_generate_and_serve_playlist
//*
//* Description: This is the real playlist path behind the non-failing
//               wrapper. It strips the request to a directory, writes a
//               temporary .playlist.m3u8, fills that file through sysOps,
//               serves it as HLS, then deletes the temp file.
//
//               Errors bubble to generate_and_serve_playlist, which shows
//               send_error_state so the client is not left hanging if
//               playlist generation fails.
//******************************************************************************
fn failable_generate_and_serve_playlist(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) !void {
    //First step... clean up the request from stream.header_target to iron out
    //the relative path we need for the file (with respect to cwd)
    const target_dir_path_padded, _ = std.mem.cutLast(u8, stream.header_target, "/") orelse return error.BadPathNoSlash;
    const target_dir_path = target_dir_path_padded[1..target_dir_path_padded.len];

    //──────────────────────────────────────────────────────────────────────────

    //Create string with relative path and filename to sort creation and
    //deletion of temporary file
    var backing_buffer_for_playlist_file_path : [128]u8 = undefined;
    const playlist_file_path = try std.fmt.bufPrint(&backing_buffer_for_playlist_file_path, "{s}/.playlist.m3u8", .{ target_dir_path });

    //Create and write playlist file
    var playlist_file = try std.Io.Dir.createFile(
        .cwd(),
        io,
        playlist_file_path,
        .{ .read = true }
    );
    defer std.Io.Dir.deleteFile(.cwd(), io, playlist_file_path) catch {};
    defer playlist_file.close(io);

    //──────────────────────────────────────────────────────────────────────────
    // Create an arraylist of the files that will need to be written to the
    // playlist file.
    // This array list - depending on the request from the client could be
    // lengthy, or it could be a single item. Using the arraylist lets us not
    // rely on the client's player settings and we can send hls and keep our
    // streaming process uniform.
    var file_list = try sysOps.get_filelist_for_playlist(
        io,
        allocator,
        stream.header_target,
    );
    defer {
        for (file_list.items) |item| {
            allocator.free(item);
        }
        file_list.deinit(allocator);
    }

    //──────────────────────────────────────────────────────────────────────────

    //Populate the playlist with data.
    try sysOps.populate_playlist_file(
        io,
        &playlist_file,
        &file_list,
        target_dir_path,
    );

    //──────────────────────────────────────────────────────────────────────────

    // Send the playlist to the client
    respond.serve_file(io, stream, &playlist_file, "application/vnd.apple.mpegurl");
}
