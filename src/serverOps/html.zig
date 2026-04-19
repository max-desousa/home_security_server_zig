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
    const file = try std.Io.Dir.openFile(.cwd(), io, sub_path, .{.allow_directory = false});
    defer file.close(io);

    var buffer_file_reader : [512]u8 = undefined;
    var file_reader = std.Io.File.reader(file, io, &buffer_file_reader);

    var buffer_body_writer : [512]u8 = undefined;
    var body_writer = try stream.request.respondStreaming(&buffer_body_writer, .{});
    defer body_writer.flush() catch {};

    //var writer = &body_writer.writer;
    //writer.noneSendFile()
    _ = try std.http.BodyWriter.noneSendFile(&body_writer.writer, &file_reader, .unlimited);

}
