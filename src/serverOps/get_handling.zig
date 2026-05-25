const std = @import("std");
const ComplexStream = @import("complexStream");
const home_page = @import("home_page.zig");
const sysOps = @import("sysOps");
const html = @import("html.zig");


//Enum for routing table
const RequestType = enum {
    Directory,
    File_RawSend,
    File_SendAsVideo,
    Home,
    Ignore,
    Playlist_PlayerSetup,
    Playlist_StreamCalculated,
    Playlist_StreamSingleFile,
};


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn classify_request_type(
    io : std.Io,
    stream : *ComplexStream,
) ?RequestType {
    //Is the request a home page?
    if (std.mem.eql(u8, stream.header_target, "/")) return .Home;

    // Checking if the request is a directory
    if (sysOps.request_is_directory(io, stream)) return .Directory;

    if (std.mem.endsWith(u8, stream.header_target, "&player=true")) return .Playlist_PlayerSetup;

    if (is_playlist_request(stream)) return .Playlist_StreamCalculated;

    if (std.mem.endsWith(u8, stream.header_target, "?m3u8")) return .Playlist_StreamSingleFile;

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

    // === DIAGNOSTIC: Log Range requests (critical for understanding seek behavior) ===
    // Headers are in head_buffer; we do a simple scan for "Range:" because arbitrary headers
    // are not exposed as a convenient map in this version of std.http.Server.
    const head_buf = stream.request.head_buffer;
    if (std.mem.indexOf(u8, head_buf, "Range:") != null or std.mem.indexOf(u8, head_buf, "range:") != null) {
        // Try to extract a reasonable slice around the header for logging
        if (std.mem.indexOf(u8, head_buf, "\r\nRange:")) |start| {
            const end = std.mem.indexOfScalarPos(u8, head_buf, start + 1, '\r') orelse head_buf.len;
            std.log.info("RANGE header present for target=\"{s}\" -> {s}", .{ stream.header_target, head_buf[start + 2 .. end] });
        } else if (std.mem.indexOf(u8, head_buf, "\r\nrange:")) |start| {
            const end = std.mem.indexOfScalarPos(u8, head_buf, start + 1, '\r') orelse head_buf.len;
            std.log.info("RANGE header present for target=\"{s}\" -> {s}", .{ stream.header_target, head_buf[start + 2 .. end] });
        } else {
            std.log.info("RANGE header present (raw scan) for target=\"{s}\"", .{ stream.header_target });
        }
    }

    // Log all video and playlist requests at info level so we can correlate with player seeks.
    // Guard by length to avoid calling unsafe suffix checks on very short targets like "/".
    if (stream.header_target.len > 4 and
        (is_video_file_request(stream) or is_playlist_request(stream)))
    {
        std.log.info("MEDIA REQUEST: method=GET target=\"{s}\"", .{ stream.header_target });
    }

    //Simplify the request type for routing.
    //On the event that the type is invalid... send "no content" response to
    //the client
    const request_type : RequestType = classify_request_type(io, stream) orelse {
        stream.request.respond(
            "",
            .{
                .status = .no_content,
            }
        ) catch {
            @panic("TODO: What do I do when server fails to reject favicon");
        };
        return;
    };

    //This is the routing table. The rest of this function SHOULD be redirects
    //to more appropriate fucntion calls. 
    switch (request_type) {
        .Home => {
            html.serve_file_from_path(
                io, 
                stream, 
                "/static/HelloWorld.html",
                "text/html; charset=utf-8",
            );
        },
        .Directory => html.generate_and_serve_directory_html(io, allocator, stream),
        .Playlist_PlayerSetup => {
            html.serve_file_from_path(
                io,
                stream,
                "/static/player.html",
                "text/html; charset=utf-8",
            );
        },
        .Playlist_StreamCalculated => generate_and_serve_playlist(io, allocator, stream),
        .File_SendAsVideo => {
            // Use the cleaner streamRemaining-based path for video segments.
            // This is more robust under the request/abort patterns generated by seeking in hls.js.
            html.serve_file_clean(
                io,
                stream,
                stream.header_target,
                "video/mp2t",
            );
        },
        .Playlist_StreamSingleFile => generate_and_serve_playlist(io, allocator, stream),

        //.File_NotVideo => {
        //    html.serve_file_from_path(
        //        io, 
        //        stream, 
        //        stream.fs_adjusted_target,
        //        "text/html; charset=utf-8",
        //    );
        //},
        //.File_Video_Downloading => {
        //    html.serve_file_from_path(
        //        io, 
        //        stream, 
        //        stream.fs_adjusted_target,
        //        "video/mp2t",
        //    );
        //},
        //.File_Video_Streaming => html.send_video_streaming(io, stream),
        //.Playlist => html.send_playlist(io, stream),
        else => unreachable,
    }

//    if (sysOps.request_is_directory(io, stream)) {
//        if (!std.mem.startsWith(u8, stream.header_target, "/Archives")) {
//            std.log.debug("We're trying to serve the static home file due to bad path\n", .{});
//            html.serve_file_from_path(
//                io,
//                stream,
//                "/static/HelloWorld.html",
//                "text/html; charset=utf-8",
//            );
//        }
//        else {
//            std.log.debug("Generic folder serving\n", .{});
//            html.generate_and_serve_directory_html(io, stream);
//        }
//    }
//    else {
//        if (request_is_for_favicon(stream)) {
//            std.log.debug("Handling a favicon request\n", .{});
//            stream.request.respond(
//                "",
//                .{
//                    .status = .no_content,
//                }
//            ) catch {
//                @panic("TODO: What do I do when server fails to reject favicon");
//            };
//        }
//        else {
//            if (is_playlist_request(stream)) {
//                if (null != std.mem.indexOf(u8, stream.header_target, "&player=true")) {
//                    html.serve_file_from_path(
//                        io,
//                        stream,
//                        "/static/player.html",
//                        "text/html; charset=utf-8",
//                    );
//                }
//                else {
//                    var file = sysOps.generate_and_get_playlist_file(
//                        io, 
//                        allocator, 
//                        stream.header_target
//                    ) catch |err| {
//                        std.log.err("Encountered error creating playlist file: {any}\n", .{ err });
//                        return;
//                    };
//                    defer file.close(io);
//
//                    html.serve_file_2(io, stream, &file, "application/vnd.apple.mpegurl");
//                }
//            }
//            else if (is_video_file_request(stream)) {
//                std.log.info("Got video request: {s}\n", .{ stream.header_target });
//                html.serve_file_from_path(
//                    io,
//                    stream,
//                    stream.header_target,
//                     //"application/vnd.apple.mpegurl",
//                     "video/mp2t",
//                );
//            }
//            else {
//                std.log.err("Unexpected request type through target: {s}\n", .{ stream.header_target });
//            }
//        }
//    }
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
        // Guard against short targets (e.g. "/" or "/foo") to prevent usize underflow
        if (stream.header_target.len < ext_len) continue;
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


//******************************************************************************
//* Function: generate_and_serve_playlist
//* 
//* Description: Wrapper for a function that can fail to generate and serve
//*              playlist. This lets us use try, and in the event of a failure,
//*              we send and forget a page to the client with an error state so
//*              that they know what's happening. 
//******************************************************************************
fn generate_and_serve_playlist(
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
        html.send_error_state(stream, error_msg);
    };
}

//******************************************************************************
//* Function: 
//* 
//* Description: 
//******************************************************************************
fn failable_generate_and_serve_playlist(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) !void {
    // Clean up the request path
    const target_dir_path_padded, _ = std.mem.cutLast(u8, stream.header_target, "/") orelse return error.BadPathNoSlash;
    const target_dir_path = target_dir_path_padded[1..target_dir_path_padded.len];

    // Get the list of video files for this playlist (reused from old logic)
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

    // Build the entire playlist in memory — this completely eliminates the
    // previous temp file race, delete timing, and file position bugs.
    var playlist_bytes: std.ArrayList(u8) = .empty;
    defer playlist_bytes.deinit(allocator);

    try sysOps.build_playlist_in_memory(
        allocator,
        &playlist_bytes,
        &file_list,
        target_dir_path,
    );

    // Serve using the robust media path (now gets Range support + good headers for free)
    // Note: playlists are small, so we can pass the bytes directly.
    html.serve_bytes_as_media(
        stream,
        playlist_bytes.items,
        "application/vnd.apple.mpegurl",
    );
}
