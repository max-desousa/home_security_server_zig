const std = @import("std");

const Self = @This();

stream : std.Io.net.Stream,
buffer_stream_writer : []u8,
buffer_stream_reader : []u8,
stream_reader : std.Io.net.Stream.Reader = undefined,
stream_writer : std.Io.net.Stream.Writer = undefined,
server : std.http.Server = undefined,
http_request : std.http.Server.Request = undefined,

pub fn init(
    io : std.Io,
    stream : std.Io.net.Stream,
    buffer_for_reading : []u8,
    buffer_for_writing : []u8,
) !Self {
    var self : Self = .{
        .stream = stream,
        .buffer_stream_writer = buffer_for_writing,
        .buffer_stream_reader = buffer_for_reading,
    };

    self.stream_reader = stream.reader(io, buffer_for_reading);
    self.stream_writer = stream.writer(io, buffer_for_writing);
    self.server = .init(&self.stream_reader.interface, &self.stream_writer.interface);
    self.http_request = try self.server.receiveHead();

    return self;
}

pub fn get_method(
    self : *Self
) !std.http.Method {
    const internal_method = self.http_request.head.method;
    switch (internal_method) {
        .POST, .GET=> {
            return internal_method;
        },
        else => {
            std.log.debug("Unexpected method found: {any}\n", .{ internal_method });
            return error.UnexpectedMethod;
        },
    }
}
