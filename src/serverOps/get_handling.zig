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
    Static,
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
            html.serve_file_from_path(
                io,
                stream,
                stream.header_target,
                 //"application/vnd.apple.mpegurl",
                 "video/mp2t",
            );
        },
        .Playlist_StreamSingleFile => generate_and_serve_playlist(io, allocator, stream),
        .Static => {
            serve_static_file(
                io,
                stream,
            ) catch |err| {
                std.debug.print("Static file serving failed due to error: {any}\n", .{ err });
            };
        },
        else => unreachable,
    }
}



//******************************************************************************
//* Function:    request_is_for_favicon
//*
//* Description: This function returns true when the last path segment of
//               the request is favicon.ico. It is present for routing so
//               browsers hammering the icon do not get treated as a real
//               file or directory request.
//
//               Currently unused by classify_request_type - the getter
//               still falls through to no-content for favicon if nothing
//               else matches.
//******************************************************************************
fn request_is_for_favicon(stream : *ComplexStream) bool {
    _, const target = std.mem.cutLast(u8, stream.header_target, "/") orelse return false;
    return std.mem.eql(u8, target, "favicon.ico");
}


//******************************************************************************
//* Function:    is_playlist_request
//*
//* Description: This is a heuristic for a calculated (time-range) playlist
//               URL. The last path segment has to contain both "start" and
//               "end" - that is the form the player uses when asking for a
//               window of archive clips rather than a single file.
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
    html.serve_file_2(io, stream, &playlist_file, "application/vnd.apple.mpegurl");
}


//******************************************************************************
//* Function: serve_static_file
//*
//* Description: We have some functions designed to serve files to the client.
//               However, those functions often require a hardcoded path to the 
//               file that they are trying to serve. The point of this function
//               is to take the requested path from the clients request and serve
//               the static file based on that. Making this function effectively
//               more reusable form. 
//
//               (Contextual Note During implementation)
//               During its implementation, this function's inputs were
//               previously confirmed to have a corresponding static loction. 
//               But, to make the function truly reusable, that check will be 
//               redone to account for future scenarios where such a distinct 
//               check may not have been done beforehand. (This is just a note
//               to any onlookers wondering why the only use case is duplicating
//               the check that the static file exists. As the project matures, 
//               this should be something that is optimized/removed.)
//******************************************************************************
fn serve_static_file(
    io : std.Io,
    stream : *ComplexStream,
    //"text/html; charset=utf-8", //Removing for the time being, is there a
                                  //content type for a static page that would
                                  //be anything other than this?
) !void {
    var path_buffer : [1024]u8 = undefined;
    const path_string = std.fmt.bufPrint(&path_buffer, "/static{s}.html", .{ stream.header_target }) catch |err| { 
        std.debug.print("TODO: What do I want to do with an error in the buffer here\n", .{});
        std.debug.print("\tThe error for this instance was: {any}\n", .{ err });
        return err;
    };

    const is_static : bool = blk: {
        std.debug.print("The path_string being evaluated is: \"{s}\"\n", .{ path_string });
        _ = std.Io.Dir.statFile(.cwd(), io, path_string[1..], .{ .follow_symlinks = false }) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!is_static) {
        return error.RequestIsNotStaticFile;
    }

    html.serve_file_from_path(
        io,
        stream,
        path_string,
        "text/html; charset=utf-8"
    );
}
