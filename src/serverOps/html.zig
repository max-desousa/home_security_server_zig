const std = @import("std");
const ComplexStream = @import("complexStream");
const sysOps = @import("sysOps");

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


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
pub fn generate_and_serve_directory_html(io : std.Io, stream : *ComplexStream) void {
    //Try creating file to generate html into if failure - respond negative response
    var file = std.Io.Dir.createFile(
            .cwd(),
            io,
            ".html_to_serve.html",
            .{
                .read = true,
                .lock = .exclusive,
            }
    ) catch {
        send_error_state(stream, "Backing file could not be secured");
        return;
    };
    defer file.close(io);

    sysOps.generate_html_for_folder(io, &file, stream.fs_adjusted_target) catch |err| {
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
//* Function:    
//*
//* Description: 
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
