const std = @import("std");


//##############################################################################
//##############################################################################
pub fn serve_page_if_requested(
    allocator : std.mem.Allocator,
    io : std.Io,
    stream : *std.Io.net.Stream,
) !bool {
    if (get_request_msg(allocator, io, stream)) |nullable_req| {
        const req = nullable_req orelse return false;
        defer allocator.free(req);
        std.debug.print("Page being requested is: {s}\n", .{req});
    } else |err| {
        return err;
    }
    return false;
}


//##############################################################################
//##############################################################################
fn get_request_msg(
    allocator : std.mem.Allocator,
    io : std.Io,
    stream : *std.Io.net.Stream,
) !?[]u8 {

    var buffer_for_stream_reader : [1024]u8 = std.mem.zeroes([1024]u8);
    var stream_reader = stream.reader(io, &buffer_for_stream_reader);

    const first_line = try stream_reader.interface.peekDelimiterExclusive('\n');
    const nullable_first_cut = std.mem.cut(u8, first_line, " ");

    const first_cut = nullable_first_cut orelse return error.BadRequestFromClient;

    if (!std.mem.eql(u8, first_cut[0], "GET")) {
        return null;
    }

    const nullable_second_cut = std.mem.cut(u8, first_cut[1], " ");
    const second_cut = nullable_second_cut orelse return error.UnknownFormatForRequest;

    // Returning the requested page to be served as a string. 
    return try std.fmt.allocPrint(allocator, "{s}", .{second_cut[0]});
}


//##############################################################################
//##############################################################################
pub fn send404(io : std.Io, stream : *std.Io.net.Stream) void {
    var buffer_for_stream_writer : [1024]u8 = std.mem.zeroes([1024]u8);
    var stream_writer_full = stream.writer(io, &buffer_for_stream_writer);
    var stream_writer = &stream_writer_full.interface;
    // Making sure flush happens - but it should be done with error checking at
    // the end. 
    defer stream_writer.flush() catch {};

    var file = std.Io.Dir.openFile(std.Io.Dir.cwd(), io, "static/404.html", .{}) catch |err| {
        std.debug.print("Error parsing 404 file: {any}\n", .{err});
        return;
    };
    defer file.close(io);

    var buffer_for_404_reader : [1024]u8 = std.mem.zeroes([1024]u8);
    var file_reader_full = file.reader(io, &buffer_for_404_reader);
    var file_reader = &file_reader_full.interface;
    _ = &file_reader;
    std.debug.print("The value of reader end is: {any}\n", .{file_reader_full.size});
    _ = file_reader_full.getSize() catch {};
    std.debug.print("The value of reader end is: {d}\n", .{file_reader_full.size.?});

    const header = 
        "HTTP/1.1 404 Not Found\r\n" ++
        "Content-Type: text/html; charset=utf-8\r\n" ++
        "Content-Length : 4301\r\n" ++
        "\r\n";
    stream_writer.writeAll(header) catch |err| {
        std.debug.print("Error sending header for 404: {any}\n", .{err});
    };

    while (file_reader_full.pos < file_reader_full.size.?) {
        std.debug.print("writing bytes...\n", .{});
        const bytes_to_read = ((file_reader_full.size.? - file_reader_full.pos) % 1024);
        const bytes = file_reader.take(bytes_to_read) catch |err| {
            std.debug.print("Error reading 404 file: {any}\n", .{err});
            return;
        };
        stream_writer.writeAll(bytes) catch |err| {
            std.debug.print("Error writing 404 to stream: {any}\n", .{err});
            return;
        };
    }

    stream_writer.flush() catch |err| {
        std.debug.print("Error flushing 404 stream: {any}\n", .{err});
    };
}
