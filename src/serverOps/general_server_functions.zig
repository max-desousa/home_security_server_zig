const std = @import("std");
const ComplexStream = @import("complexStream");
const config = @import("config");
const get = @import("get_handling.zig");
const post = @import("post_handling.zig");

var ConnectionLog : std.ArrayList(ConnectionEntry) = .empty;

const ConnectionEntry = struct {
    ip_addr : std.Io.net.IpAddress,
    camera_name : []const u8,
    last_update : u64,
};

pub fn is_client_recognized_camera(
    complexStream : *ComplexStream
) bool {
    for (ConnectionLog.items) |connectionEntry| {
        const match : bool = std.Io.net.IpAddress.eql(
            &complexStream.stream.socket.address,
            &connectionEntry.ip_addr,
        );
        if (match) return true;
    }
    return false;
}

pub fn send_client_to_login(stream : *ComplexStream) !void {
    try stream.request.respond(
        "",
        .{
            .status = .see_other,
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "Location", .value = "/login" },
            },
        }
    );
}


pub fn stream_processing(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) void {
    const method = stream.get_method() catch |err| {
        std.log.err("Could not find method due to error: {any}\n", .{ err });
        return;
    };

    //if ((!std.mem.eql(u8, stream.header_target, "/login")) and 
    //    (config.is_valid_cookie(stream.cookie_token.?))) {
    //    const validClient : bool = serverOps.general.is_client_recognized_camera(stream);
    //    if (!validClient) {
    //        serverOps.general.send_client_to_login(stream) catch {
    //            @panic("TODO: how do I want to handle failing to redirect?");
    //        };
    //        return;
    //        //@panic("TODO: send rejection due to client not being in the client log");
    //    }
    //}


    switch(method) {
        .GET => get.generic_getter(io, allocator, stream),
        .POST => post.generic_poster(allocator, io, stream), 
        else => {
            //std.log.info("Received an unsupported http request (method: {s}) on thread {d}\n", .{ @tagName(method), thread_num });
            std.log.info("Received an unsupported http request (method: {s})\n", .{ @tagName(method) });
        },
    }
}
