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

    sysOps.generate_html_for_folder(io, &file, stream.target_file_system_path.?) catch |err| {
        std.log.err("Failed dir html generation due to error {any}\n", .{ err });
        send_error_state(stream, "Error generating your view of the directory");
    };

    serve_file_2(io, stream, &file);
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn serve_file_2(io : std.Io, stream : *ComplexStream, file : *std.Io.File) void {
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

    var backing_buffer_for_reader : [1024]u8 = undefined;
    var file_reader = file.reader(io, &backing_buffer_for_reader);

    _ = file_reader.interface.streamRemaining(&body_writer.writer) catch {};
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
