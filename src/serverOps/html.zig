const std = @import("std");
const ComplexStream = @import("complexStream");

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
fn generate_and_serve_directory_html() void {
}
