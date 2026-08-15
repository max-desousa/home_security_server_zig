//! HTTP-method switch after a request has already passed the gate.
//!
//! This file only decides GET vs POST (or drop). Target routing lives in
//! `get.zig` / `post.zig`. Implementations (playlist, archive, login, file
//! send) live in their own files.

const std = @import("std");
const ComplexStream = @import("complexStream");
const get = @import("get.zig");
const post = @import("post.zig");

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

    switch(method) {
        .GET => get.generic_getter(io, allocator, stream),
        .POST => post.generic_poster(allocator, io, stream),
        else => {
            std.log.info("Received an unsupported http request (method: {s})\n", .{ @tagName(method) });
        },
    }
}
