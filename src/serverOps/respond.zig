//! Primitive HTTP responses: stream a file, send 204, or send an error page.
//!
//! Feature orchestration (directory listing, playlist generation) does not
//! live here — those files call into this one to send the result.

const std = @import("std");
const ComplexStream = @import("complexStream");


//******************************************************************************
//* Function:    send_no_content
//*
//* Description: Empty 204 so the client is not left spinning on a target
//               GET routing did not recognize.
//******************************************************************************
pub fn send_no_content(stream : *ComplexStream) void {
    stream.request.respond(
        "",
        .{
            .status = .no_content,
        }
    ) catch {
        @panic("TODO: What do I do when server fails to reject favicon");
    };
}


//******************************************************************************
//* Function:    serve_file_from_path
//*
//* Description: This function opens a path (skipping the leading '/' so it
//               is cwd-relative) and forwards the file to serve_file with
//               the caller-supplied Content-Type. Open failure is reported
//               to the client as an error page rather than bubbling out.
//
//               This is the convenient entry for GET routing when the
//               target is already known (home, player.html, video files).
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
    serve_file(io, stream, &file, content_type);
}

//******************************************************************************
//* Function:    serve_file
//*
//* Description: This is the shared send path. It builds a streaming
//               response with the given Content-Type and copies the file in
//               fill/toss chunks. Directory listings, playlists, and
//               static/video GETs all eventually hit this function.
//
//               The chunked copy is intentional - some of these files can
//               be large video clips, and we do not want to require the
//               whole file in memory before the first byte goes out.
//******************************************************************************
pub fn serve_file(
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
    while (true) {
        file_reader.interface.fillMore() catch |err| {
            std.log.err("Error reading from file: {any}\n", .{ err });
            break;
        };
        defer file_reader.interface.toss(file_reader.interface.bufferedLen());
        std.log.debug("We did read at least once successfully\n", .{});

        if (0 == file_reader.interface.buffer.len) break;

        body_writer.writer.writeAll(backing_buffer_for_reader[0..file_reader.interface.bufferedLen()]) catch |err| {
            std.log.err("Error writing to stream: {any}\n", .{ err });
            break;
        };
    }
}


//******************************************************************************
//* Function:    send_error_state
//*
//* Description: This is the last-resort HTML error page so the browser is
//               not left spinning when something in serving or generation
//               fails. The status string is interpolated into a small
//               "Server has entered error state" document.
//
//               Wrappers that catch errors (playlist generation, directory
//               HTML, file open) call this instead of returning a bare
//               status with no body.
//******************************************************************************
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
