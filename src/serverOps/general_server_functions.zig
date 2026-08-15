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

//******************************************************************************
//* Function:    is_client_recognized_camera
//*
//* Description: This function checks the connection log to see if this
//               stream's IP is already known as a camera. The idea is that
//               once a camera has identified itself, later requests from
//               that address can skip the human-login path.
//
//               Currently unused by the live routing path (the old call in
//               stream_processing is commented out) but this is still the
//               lookup against that log.
//******************************************************************************
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

//******************************************************************************
//* Function:    send_client_to_login
//*
//* Description: This function sends a 303 redirect to /login with no body.
//               connection_router uses this when authenticated_user_check
//               fails, so the client is pointed at login instead of being
//               left hanging on the resource they asked for.
//******************************************************************************
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


//******************************************************************************
//* Function:    stream_processing
//*
//* Description: This function is the method switch after a client has
//               already passed the auth check. GET is handed to
//               generic_getter, POST to generic_poster, and anything else is
//               logged and dropped.
//
//               The point of keeping this here (instead of in the thread
//               itself) is so the router thread stays a hand-off point and
//               the HTTP verb routing lives with the rest of serverOps.
//******************************************************************************
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
