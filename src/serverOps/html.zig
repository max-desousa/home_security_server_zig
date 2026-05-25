const std = @import("std");
const ComplexStream = @import("complexStream");
const sysOps = @import("sysOps");

const HTML_FILE_TO_SERVE = ".html_to_serve.html";

pub fn serve_file(
    io : std.Io,
    stream : *ComplexStream,
    sub_path : []const u8,
) !void {
    const file = try std.Io.Dir.openFile(.cwd(), io, sub_path, .{.allow_directory = false});
    defer file.close(io);

    var buffer_file_reader : [512]u8 = undefined;
    var file_reader = std.Io.File.reader(file, io, &buffer_file_reader);

    var buffer_body_writer : [512]u8 = undefined;
    var body_writer = try stream.request.respondStreaming(&buffer_body_writer, .{});
    defer body_writer.end() catch {};

    _ = try file_reader.interface.streamRemaining(&body_writer.writer);
}

/// Robust media file serving with:
/// - Range request support (206 Partial Content) for seeking/scrubbing
/// - Content-Length when possible (better for HLS players than pure chunked)
/// - Proper Accept-Ranges header
/// - Graceful handling of client aborts during seeks
pub fn serve_file_clean(
    io : std.Io,
    stream : *ComplexStream,
    file_path : []const u8,
    content_type : []const u8,
) void {
    const fs_path = file_path[1..];

    // Get file size first (needed for Content-Length and Range handling)
    const file_stat = std.Io.Dir.statFile(.cwd(), io, fs_path, .{}) catch {
        send_media_error(stream, .not_found, "Media file not found");
        return;
    };
    const file_size = file_stat.size;

    const file = std.Io.Dir.openFile(.cwd(), io, fs_path, .{}) catch {
        send_media_error(stream, .not_found, "Media file not found");
        return;
    };
    defer file.close(io);

    // Check for Range header - improved detection
    const head_buf = stream.request.head_buffer;
    const range_header = blk: {
        // Try several common forms (case insensitive where practical)
        const patterns = [_][]const u8{
            "Range: bytes=",
            "range: bytes=",
            "Range:bytes=",
            "range:bytes=",
        };
        for (patterns) |pat| {
            if (std.mem.indexOf(u8, head_buf, pat)) |pos| {
                const start_pos = pos + pat.len;
                const end_pos = std.mem.indexOfScalarPos(u8, head_buf, start_pos, '\r') orelse
                            std.mem.indexOfScalarPos(u8, head_buf, start_pos, '\n') orelse head_buf.len;
                break :blk std.mem.trim(u8, head_buf[start_pos..end_pos], " \t");
            }
        }
        break :blk null;
    };

    var start: u64 = 0;
    var end: u64 = file_size - 1;
    var is_range_request = false;

    if (range_header) |rh| {
        if (std.mem.indexOfScalar(u8, rh, '-')) |dash| {
            is_range_request = true;
            if (dash > 0) {
                start = std.fmt.parseInt(u64, rh[0..dash], 10) catch 0;
            }
            if (dash + 1 < rh.len) {
                end = std.fmt.parseInt(u64, rh[dash + 1 ..], 10) catch (file_size - 1);
            }
        }
        if (start > file_size) start = file_size;
        if (end >= file_size) end = file_size - 1;
        if (start > end) {
            start = 0;
            end = file_size - 1;
            is_range_request = false;
        }
    }

    const content_length: u64 = if (is_range_request) (end - start + 1) else file_size;
    const status: std.http.Status = if (is_range_request) .partial_content else .ok;

    // === Visible diagnostics for debugging the seeking/buffering issue ===
    if (std.mem.indexOf(u8, content_type, "video/") != null or std.mem.indexOf(u8, content_type, "mp2t") != null) {
        if (is_range_request) {
            std.log.info("MEDIA SERVE: RANGE request for {s}  bytes={d}-{d}/{d} (len={d})", .{
                fs_path, start, end, file_size, content_length,
            });
        } else {
            std.log.info("MEDIA SERVE: full segment {s}  size={d}", .{ fs_path, file_size });
        }
    }

    // Build headers without dynamic allocation for simplicity/reliability
    var content_range_buf: [128]u8 = undefined;
    var cl_buf: [32]u8 = undefined;
    const cl_str = std.fmt.bufPrint(&cl_buf, "{d}", .{content_length}) catch "0";

    // Use a fixed-size array so both branches have compatible types
    var headers_arr: [6]std.http.Header = undefined;
    var header_count: usize = 0;

    headers_arr[header_count] = .{ .name = "Content-Type", .value = content_type };
    header_count += 1;

    headers_arr[header_count] = .{ .name = "Accept-Ranges", .value = "bytes" };
    header_count += 1;

    headers_arr[header_count] = .{ .name = "Content-Length", .value = cl_str };
    header_count += 1;

    if (is_range_request) {
        const cr = std.fmt.bufPrint(&content_range_buf, "bytes {d}-{d}/{d}", .{ start, end, file_size }) catch "bytes */*";
        headers_arr[header_count] = .{ .name = "Content-Range", .value = cr };
        header_count += 1;
    }

    // Strong caching for immutable video segments (.ts files etc.)
    // This is frequently the missing piece that makes heavy seeking much more stable in browsers.
    if (std.mem.indexOf(u8, content_type, "video/") != null or
        std.mem.indexOf(u8, content_type, "mp2t") != null)
    {
        headers_arr[header_count] = .{
            .name = "Cache-Control",
            .value = "public, max-age=31536000, immutable",
        };
        header_count += 1;

        // Simple but effective ETag using size + mtime (nanoseconds)
        var etag_buf: [64]u8 = undefined;
        const etag = std.fmt.bufPrint(&etag_buf, "\"{d}-{d}\"", .{ file_size, file_stat.mtime.nanoseconds }) catch "\"\"";
        headers_arr[header_count] = .{ .name = "ETag", .value = etag };
        header_count += 1;
    }

    var buffer_body_writer: [4096]u8 = undefined;
    var body_writer = stream.request.respondStreaming(
        &buffer_body_writer,
        .{
            .respond_options = .{
                .status = status,
                .extra_headers = headers_arr[0..header_count],
            },
        },
    ) catch |err| {
        std.log.err("Failed to start media response: {any}", .{err});
        return;
    };
    defer body_writer.end() catch {};

    if (is_range_request) {
        // Use positional read for the exact range - this is efficient and avoids offset issues
        var remaining = content_length;
        var offset = start;
        var temp_buf: [8192]u8 = undefined;

        while (remaining > 0) {
            const to_read = @min(remaining, temp_buf.len);
            const n = file.readPositional(io, &.{temp_buf[0..to_read]}, offset) catch |err| {
                std.log.debug("Positional read aborted during Range request (likely client seek): {any}", .{err});
                break;
            };
            if (n == 0) break;
            body_writer.writer.writeAll(temp_buf[0..n]) catch |err| {
                std.log.debug("Client aborted media Range response: {any}", .{err});
                break;
            };
            offset += n;
            remaining -= n;
        }
    } else {
        // Full file - use the clean streamRemaining path
        var buffer_file_reader: [8192]u8 = undefined;
        var file_reader = std.Io.File.reader(file, io, &buffer_file_reader);

        _ = file_reader.interface.streamRemaining(&body_writer.writer) catch {
            std.log.info("MEDIA SERVE: client aborted full segment {s} (seek in progress)", .{fs_path});
        };
    }

    if (std.mem.indexOf(u8, content_type, "video/") != null or std.mem.indexOf(u8, content_type, "mp2t") != null) {
        std.log.info("MEDIA SERVE: finished {s} (ranged={})", .{ fs_path, is_range_request });
    }
}

/// Simple helper to serve pre-built bytes (primarily for in-memory m3u8 playlists).
/// Gives us consistent headers and the same robustness as file serving.
pub fn serve_bytes_as_media(
    stream: *ComplexStream,
    bytes: []const u8,
    content_type: []const u8,
) void {
    var buffer: [1024]u8 = undefined;
    const cl = std.fmt.bufPrint(&buffer, "{d}", .{bytes.len}) catch "0";

    var h: [4]std.http.Header = .{
        .{ .name = "Content-Type", .value = content_type },
        .{ .name = "Content-Length", .value = cl },
        .{ .name = "Accept-Ranges", .value = "bytes" },
        .{ .name = "Cache-Control", .value = "no-cache" },
    };

    var w = stream.request.respondStreaming(&buffer, .{
        .respond_options = .{ .extra_headers = h[0..] },
    }) catch |err| {
        std.log.err("Failed to respond with in-memory media: {any}", .{err});
        return;
    };
    defer w.end() catch {};

    w.writer.writeAll(bytes) catch |err| {
        std.log.debug("Client aborted playlist/bytes response: {any}", .{err});
    };
}


//******************************************************************************
//* Function:    
//*
//* Description: 
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
        send_error_state(stream, "Backing file could not be secured");
        return;
    };
    defer std.Io.Dir.deleteFile(.cwd(), io, HTML_FILE_TO_SERVE) catch |err| {
        std.log.err("Could not delete the temporary file used for html view of directory due to error: {any}", .{ err });
    };
    defer file.close(io);

    sysOps.generate_html_for_folder(io, allocator, &file, stream.fs_adjusted_target) catch |err| {
        std.log.err("Failed dir html generation due to error {any}\n", .{ err });
        send_error_state(stream, "Error generating your view of the directory");
    };

    serve_file_2(io, stream, &file, "text/html; charset=utf-8");
}


//******************************************************************************
//* Function: 
//* 
//* Description: 
//******************************************************************************
pub fn serve_file_from_path(
    io : std.Io,
    stream : *ComplexStream,
    file_path : []const u8,
    content_type : []const u8,
) void {
    var file = std.Io.Dir.openFile(.cwd(), io, file_path[1..], .{}) catch {
        send_error_state(stream, "Server could not open requested file.");
        return;
    };
    defer file.close(io);
    serve_file_2(io, stream, &file, content_type);
}

//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
pub fn serve_file_2(
    io : std.Io,
    stream : *ComplexStream,
    file : *std.Io.File,
    content_type : []const u8
) void {
    var backing_buffer_for_response : [1024]u8 = undefined;
    var body_writer = stream.request.respondStreaming(
        &backing_buffer_for_response,
        .{
            .respond_options = .{
                .extra_headers = &.{
                    //.{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                    .{ .name = "Content-Type", .value = content_type },
                },
            },
        },
    ) catch |err| {
        std.debug.print("Error: \"{any}\" occurred when attempting to respond to the client", .{ err });
        @panic("TODO: What do you do when you can not respond to request?");
    };
    defer body_writer.end() catch {};

    var backing_buffer_for_reader : [1024]u8 = std.mem.zeroes([1024]u8);
    var file_reader = file.reader(io, &backing_buffer_for_reader);

    // === DIAGNOSTIC LOGGING for video/playlist serving (helps debug seek buffering) ===
    const is_video_or_playlist = std.mem.indexOf(u8, content_type, "video/") != null or
        std.mem.indexOf(u8, content_type, "mpegurl") != null or
        std.mem.indexOf(u8, content_type, "mp2t") != null;

    if (is_video_or_playlist) {
        std.log.info("SERVE_FILE_2 START: content_type=\"{s}\" reader_pos_before_loop={d}", .{
            content_type,
            file_reader.pos,
        });
    }

    //_ = file_reader.interface.streamRemaining(&body_writer.writer) catch {};
    //std.log.debug("Flushing the body writer...\n", .{});
    //body_writer.flush() catch |err| {
    //    std.log.err("There was an error flushing the body writer: {any}\n", .{ err });
    //};
    //body_writer.endChunked(.{}) catch |err| {
    //    std.log.err("There was an issue ending the chunked transfer: {any}\n", .{ err });
    //};

    if (file_reader.atEnd()) {
        std.log.err("My Reader indicates that we are at the end of the file\n", .{});
    }
    else {
        std.log.debug("Not at end of file. The position of the reader before starting is: {d}\n", .{ file_reader.pos });
    }
    var chunk_count: usize = 0;
    while (true) {
        file_reader.interface.fillMore() catch |err| {
            std.log.err("Error reading from file: {any}\n", .{ err });
            break;
        };
        defer file_reader.interface.toss(file_reader.interface.bufferedLen());
        std.log.debug("We did read at least once successfully\n", .{});

        const buffered = file_reader.interface.bufferedLen();
        if (0 == file_reader.interface.buffer.len) break;

        if (is_video_or_playlist) {
            chunk_count += 1;
            std.log.info("SERVE_FILE_2 CHUNK #{d}: buffered_len={d} writing_from_backing[0..{d}] reader_pos={d}", .{
                chunk_count,
                buffered,
                buffered,
                file_reader.pos,
            });
        }

        body_writer.writer.writeAll(backing_buffer_for_reader[0..buffered]) catch |err| {
            std.log.err("Error writing to stream: {any}\n", .{ err });
            break;
        };
    }

    if (is_video_or_playlist) {
        std.log.info("SERVE_FILE_2 END: total_chunks={d}", .{chunk_count});
    }
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
/// Sends an error response with a specific HTTP status code.
/// Preferred for media (video/playlist) errors so players see real 404/500 instead of 200+HTML.
pub fn send_media_error(stream : *ComplexStream, status_code: std.http.Status, message: []const u8) void {
    const body = message; // keep it minimal
    _ = stream.request.respond(body, .{
        .status = status_code,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "text/plain; charset=utf-8" },
        },
    }) catch {};
}

/// Legacy HTML error page (kept for directory views and non-media errors)
pub fn send_error_state(stream : *ComplexStream, status : []const u8) void {
    var backing_buffer_for_response : [1024]u8 = undefined;
    var body_writer = stream.request.respondStreaming(
        &backing_buffer_for_response,
        .{
        },
    ) catch |err| {
        std.debug.print("Error: \"{any}\" occurred when attempting to respond to the client", .{ err });
        @panic("TODO: What do you do when you can not respond to request?");
    };
    defer body_writer.end() catch {};

    const starting_text = 
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>Server Error</title>
        \\    <style>
        \\        body {
        \\            font-family: system-ui, -apple-system, sans-serif;
        \\            background: #f8f9fa;
        \\            color: #333;
        \\            text-align: center;
        \\            padding: 60px 20px;
        \\        }
        \\        h1 {
        \\            color: #d9534f;
        \\            font-size: 28px;
        \\        }
        \\        p {
        \\            font-size: 18px;
        \\            max-width: 600px;
        \\            margin: 20px auto;
        \\        }
        \\    </style>
        \\</head>
        \\<body>
        \\
        ;

    body_writer.writer.writeAll(starting_text) catch {
        @panic("Could not write all...");
    };
    body_writer.writer.print("    <h1>Server has entered error state: \"{s}\"</h1>\n", .{ status }) catch {
        @panic("Could not write status...");
    };
    const ending_text = 
        \\    <p>Please try again and let the engineer know about the issue/conditions.</p>
        \\</body>
        \\</html>
        ;
    body_writer.writer.writeAll(ending_text) catch {
        @panic("Could not write all...");
    };
}
