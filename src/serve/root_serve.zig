const std = @import("std");
const middleware = @import("middleware.zig").all;
const post_handler = @import("post_handler.zig").run;
const get_handler = @import("get_handler.zig").run;
const Request = @import("request");

const RequestType = enum {
    POST,
    GET,
    INVALID,
};

pub fn server_main(
    allocator : std.mem.Allocator,
    io : std.Io,
    stream : *std.Io.net.Stream
) !void {
    var req = try Request.init(allocator, io, stream);
    defer req.deinit() catch {};

    //try middleware.all(stream);
    middleware(&req) catch |err| {
        std.debug.print("Middleware is failing with error: {any}\n", .{err});
        return;
    };
    switch (req.method) {
        .POST => try post_handler(stream),
        .GET => try get_handler(&req),
        else => try send_404(&req),
    }
}

fn send_404(req : *Request) !void {
    _ = &req;
}
