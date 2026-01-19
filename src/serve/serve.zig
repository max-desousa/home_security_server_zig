const std = @import("std");
const Request = @import("request");

pub fn send_home_page(req : *Request) !void {
    var file = std.Io.Dir.openFile(
        std.Io.Dir.cwd(),
        req.io,
        "static/HelloWorld.html",
        .{},
    ) catch |err| {
        std.debug.print("Error finding path ({s}) in static directory\n", .{req.req_uri});
        std.debug.print("\tError code: {any}\n", .{err});
        std.debug.print("\t(serving 404)\n", .{});
        return;
    };
    defer file.close(req.io);

    try serve_successful_static_file(req.io, file, req.stream);
}



pub fn serve_successful_static_file(
    io : std.Io,
    file : std.Io.File,
    stream : *std.Io.net.Stream
) !void {
    const buffer_sizes : usize = 2056;
    var buffer_for_file_reader : [buffer_sizes]u8 = std.mem.zeroes([buffer_sizes]u8);

    var file_reader_full = file.reader(io, &buffer_for_file_reader);
    var file_reader = &file_reader_full.interface;

    const file_size = try file_reader_full.getSize();

    var buffer_for_header : [4096]u8 = std.mem.zeroes([4096]u8);
    const header = try std.fmt.bufPrint(
        &buffer_for_header,
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/html; charset=utf-8\r\n" ++
        "Content-Length: {d}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n",
        .{file_size}
    );

    var buffer_for_stream_writer : [buffer_sizes]u8 = std.mem.zeroes([buffer_sizes]u8);
    var stream_writer_full = stream.writer(io, &buffer_for_stream_writer);
    defer stream_writer_full.interface.flush() catch {};
    var stream_writer = &stream_writer_full.interface;

    try stream_writer.writeAll(header);

    while (file_reader_full.pos < file_size) {
        const remaining_bytes = file_size - file_reader_full.pos;
        const bytes_to_transfer = @min(buffer_sizes, remaining_bytes);
        const bytes = try file_reader.take(bytes_to_transfer);
        try stream_writer.writeAll(bytes);
    }
    try stream_writer_full.interface.flush();
}


pub fn send204(req : *Request) !void {
    const buffer_sizes : usize = 2056;

    var buffer_for_header : [buffer_sizes]u8 = std.mem.zeroes([buffer_sizes]u8);
    const header = try std.fmt.bufPrint(
        &buffer_for_header,
        "HTTP/1.1 204 OK\r\n" ++
        "Connection: close\r\n",
        .{}
    );

    var buffer_for_stream_writer : [buffer_sizes]u8 = std.mem.zeroes([buffer_sizes]u8);
    var stream_writer_full = req.stream.writer(req.io, &buffer_for_stream_writer);
    defer stream_writer_full.interface.flush() catch {};
    var stream_writer = &stream_writer_full.interface;

    try stream_writer.writeAll(header);

    try stream_writer_full.interface.flush();
    std.debug.print("---Sent 204---\n", .{});
}

//pub fn send404(req : *Request) !void {
//
//    var nullable_file = try find_static_file(req.io, "404");
//    var file = nullable_file orelse blk: {
//        try send_basic_404();
//        return;
//    };
//
//    try serve_successful_static_file(req.io, file req.stream);
//}
