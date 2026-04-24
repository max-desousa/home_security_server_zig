const std = @import("std");
const ComplexStream = @import("complexStream");

pub fn serve(
    io : std.Io,
    allocator : std.mem.Allocator, 
    stream : *ComplexStream,
    sub_path : []const u8,
) !void {
    _ = &allocator;
    _ = &stream;
const file = try std.Io.Dir.openFile(.cwd(), io, sub_path, .{ .allow_directory = false });
    defer file.close(io);

    const stat = try file.stat(io);  // Get size for Content-Length
    const file_size = stat.size;

    // Choose MIME type based on extension (simple example)
    //const content_type = if (std.mem.endsWith(u8, sub_path, ".html")) "text/html"
    //    else if (std.mem.endsWith(u8, sub_path, ".css")) "text/css"
    //    else if (std.mem.endsWith(u8, sub_path, ".js")) "application/javascript"
    //    else "application/octet-stream";

    var buffer_file_reader: [64]u8 = undefined;  // larger buffer is better
    var file_reader = std.Io.File.reader(file, io, &buffer_file_reader);

    var buffer_body_writer : [64]u8 = undefined;

    // === THIS IS THE KEY PART ===
    var body_writer = try stream.request.respondStreaming(
        &buffer_body_writer,  // your 512-byte buffer (or larger)
        .{},
        //.{
        //    .respond_options = .{
        //        .status = .ok,  // 200 OK
        //        .extra_headers = &[_]std.http.Header{
        //            .{ .name = "Content-Type", .value = content_type },
        //            .{ .name = "Content-Length", .value = try std.fmt.allocPrint(allocator, "{d}", .{file_size}) },
        //            // .{ .name = "Connection", .value = "close" }, // optional
        //        },
        //    },
        //},
    );
    defer body_writer.end() catch |err| {
        std.debug.print("Error ending body writer: {any}\n", .{ err });
    };  // still good to have

    std.debug.print("Streaming file {s} ({d} bytes)...\n", .{ sub_path, file_size });

    const bytes_written = try (&file_reader.interface).streamRemaining(&body_writer.writer);

    std.debug.print("Streamed {d} bytes.\n", .{bytes_written});
}
