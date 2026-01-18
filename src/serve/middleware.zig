const std = @import("std");
const Request = @import("request");

pub fn all(
    req : *Request,
) !void {
    try discard_favicon_requests(req);
}

fn discard_favicon_requests(
    req : *Request,
) !void {
    std.debug.print("Sanity check 1...\n", .{});
    if (.GET != req.type) {
        return;
    }
    std.debug.print("Sanity check 2...\n", .{});

    var buffer_for_stream_reader : [1024]u8 = std.mem.zeroes([1024]u8);
    var stream_reader = req.*.stream.*.reader(req.*.io, &buffer_for_stream_reader);
    std.debug.print("Sanity check 3...\n", .{});

    const first_line = try stream_reader.interface.peekDelimiterExclusive('\r');
    std.debug.print("Sanity check 4...\n", .{});
    if (std.mem.eql(u8, first_line, "GET /favicon.ico")) {
        return error.IgnoreFavicon;
    }
}
