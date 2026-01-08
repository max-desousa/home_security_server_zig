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
pub fn parse_and_serve_req_path(
    allocator : std.mem.Allocator,
    io : std.Io,
    stream : *std.Io.net.Stream,
) !void {
    const nullable_req = get_request_msg(allocator, io, stream) catch |err| {
        std.debug.print("Issue parsing request message: {any}", .{err});
        return err;
    };
    const req = nullable_req orelse {
        std.debug.print("Server only supports `GET` messages so far - hitting unimplemented logic\n", .{});
        return error.NotAGetRequest;
    };
    defer allocator.free(req);

    std.debug.print("Assessing request: {s}\n", .{req});

    const hard_coded_path : bool = try serve_hard_coded_request(io, req, stream);
    if (hard_coded_path) {
        return;
    }

    try serve_requested_path(io, req, stream);
}


//##############################################################################
//##############################################################################
pub fn serve_requested_path(io : std.Io, req : []u8, stream : *std.Io.net.Stream) !void {
    var modified_path_buffer : [512]u8 = std.mem.zeroes([512]u8);
    const modified_path = try std.fmt.bufPrint(&modified_path_buffer, "static{s}", .{req});

    var file = std.Io.Dir.openFile(
        std.Io.Dir.cwd(),
        io,
        modified_path,
        .{},
    ) catch |err| {
        std.debug.print("Error finding path ({s}) in static directory\n", .{req});
        std.debug.print("\tError code: {any}\n", .{err});
        std.debug.print("\t(serving 404)\n", .{});
        send404(io, stream);
        return;
    };
    defer file.close(io);
    try serve_successful_static_file(io, file, stream);
}

pub fn serve_not_supported_content(
    io : std.Io,
    stream : *std.Io.net.Stream,
) !void {
    const text_to_send = 
        "HTTP/1.1 204 No Content\r\n" ++
        "Content-Length: 0\r\n" ++
        "Cache-Control: public, max-age=31536000, immutable\r\n" ++
        "Connection: close\r\n" ++
        "\r\n";

    var buffer_for_stream : [256]u8 = std.mem.zeroes([256]u8);
    var stream_writer_full = stream.writer(io, &buffer_for_stream);
    defer stream_writer_full.interface.flush() catch {};

    stream_writer_full.interface.writeAll(text_to_send) catch |err| {
        std.debug.print("Issues writing to stream in `serve_not_supported_content`\n", .{});
        return err;
    };
    stream_writer_full.interface.flush() catch |err| {
        std.debug.print("Error flushing in `serve_not_supported_content`\n", .{});
        return err;
    };
}

//##############################################################################
//##############################################################################
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

    var file_size_buffer : [16]u8 = std.mem.zeroes([16]u8);
    const file_size_string = std.fmt.bufPrint(
        &file_size_buffer, 
        "{d}", .
        {file_reader_full.size.?}
    ) catch |err| {
        std.debug.print("Error in getting 404 file size as string: {any}\n", .{err});
        return;
    };

    const header_part_one = 
        "HTTP/1.1 404 Not Found\r\n" ++
        "Content-Type: text/html; charset=utf-8\r\n" ++
        "Content-Length: ";
    stream_writer.writeAll(header_part_one) catch |err| {
        std.debug.print("Error sending header (part one) for 404: {any}\n", .{err});
    };
    stream_writer.writeAll(file_size_string) catch |err| {
        std.debug.print("Error sending header (file size string) for 404: {any}\n", .{err});
    };
    const header_part_two = 
        "\r\n" ++ //finishing the content length line
        "\r\n";   //blank line to seperate content
    stream_writer.writeAll(header_part_two) catch |err| {
        std.debug.print("Error sending header (part two) for 404: {any}\n", .{err});
    };

    while (file_reader_full.pos < file_reader_full.size.?) {
        std.debug.print("writing bytes...\n", .{});
        const bytes_remaining = file_reader_full.size.? - file_reader_full.pos;
        const bytes_to_read = @min(1024, bytes_remaining);
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


//##############################################################################
//
//##############################################################################
fn serve_hard_coded_request(
    io : std.Io, 
    req : []u8, 
    stream : *std.Io.net.Stream
) !bool {

    std.debug.print("Entered hard coded function...\n", .{});

    if (std.mem.eql(u8, "/favicon.ico", req)) {
        try serve_not_supported_content(io, stream);
        return true;
    }

    if (std.mem.eql(u8, "/", req)) {
        std.debug.print("Home page redirect\n", .{});
        var home_path_buffer : [32]u8 = std.mem.zeroes([32]u8);
        const home_path = try std.fmt.bufPrint(&home_path_buffer, "/HelloWorld.html", .{});
        try serve_requested_path(io, home_path, stream);
        return true;
    }
    std.debug.print("i didn't expect to hit this...\n", .{});

    return false;
}
