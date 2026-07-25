const std = @import("std");

const Self = @This();

const BUFFER_SIZE_FOR_HEADER_FIELDS = 512;

// Underlying (backing) stream
stream : std.Io.net.Stream,

// Necessary elements for zig's server parsing - sever needs a reader and writer
// zig's library to help with http parsing needs the std.Io.net.Stream's reader
// and writer to enable handling parsing and responding... but these should not
// be touched... they are BACKING writers... hidden under a few layers writing 
// the raw bitstreams... not the ease of access in handling http compliance...
// that's another set of readers/writers. 
backing_buffer_for_raw_stream_writer : []u8,
backing_buffer_for_raw_stream_reader : []u8,
raw_stream_reader : std.Io.net.Stream.Reader = undefined,
raw_stream_writer : std.Io.net.Stream.Writer = undefined,

// The "server" object that we'll reference when parsing the body etc (backed by the stream)
server : std.http.Server = undefined,
request : std.http.Server.Request = undefined,

// Fields to cache all necessary header information necessary
// (The state of reading the headers seems transient - so we have greater success
// parsing everything immediately)
backing_buffer_for_target : [BUFFER_SIZE_FOR_HEADER_FIELDS]u8 = std.mem.zeroes([BUFFER_SIZE_FOR_HEADER_FIELDS]u8),
header_target : []u8 = undefined,
header_method : ?std.http.Method = null,

//We need a field to parse the header and store the user's cookies.
cookie_token : ?[]u8 = null,

backing_buffer_for_fs_adjusted_target : [BUFFER_SIZE_FOR_HEADER_FIELDS]u8 = std.mem.zeroes([BUFFER_SIZE_FOR_HEADER_FIELDS]u8),
fs_adjusted_target : []u8 = undefined,


//------------------------------ BEGIN METHODS ---------------------------------


pub fn create(
    stream : std.Io.net.Stream,
    buffer_for_reading : []u8,
    buffer_for_writing : []u8,
) !Self {
    return .{
        .stream = stream,
        .backing_buffer_for_raw_stream_writer = buffer_for_writing,
        .backing_buffer_for_raw_stream_reader = buffer_for_reading,
    };
}

pub fn setup(
    self : *Self,
    io : std.Io,
) !void {
    self.raw_stream_reader = self.stream.reader(io, self.backing_buffer_for_raw_stream_reader);
    self.raw_stream_writer = self.stream.writer(io, self.backing_buffer_for_raw_stream_writer);
    self.server = .init(&self.raw_stream_reader.interface, &self.raw_stream_writer.interface);
    self.header_target = &self.backing_buffer_for_target;

    try self.cache_headers();
}


//******************************************************************************
// Function: cache_headers
//
// Description:
//******************************************************************************
fn cache_headers(self : *Self) !void {
    self.request = try self.server.receiveHead();
    self.header_method = self.request.head.method;
    if (1 == self.request.head.target.len) {
        self.fs_adjusted_target = std.fmt.bufPrint(
            &self.backing_buffer_for_fs_adjusted_target,
            ".",
            .{}
        ) catch @panic("Problem modifying header request with prepended period (root)");
    }
    else {
        self.fs_adjusted_target = std.fmt.bufPrint(
            &self.backing_buffer_for_fs_adjusted_target,
            ".{s}",
            .{ self.request.head.target }
        ) catch @panic("Problem modifying header request with prepended period (not root)");
    }
    @memcpy(self.backing_buffer_for_target[0..self.request.head.target.len], self.request.head.target);
    self.header_target = self.backing_buffer_for_target[0..self.request.head.target.len];
    std.log.debug("Header target is: {s}\n", .{ self.header_target });

    //Here we will evaluate cookies if there are any:
    var headerIterator = self.request.iterateHeaders();
    while (headerIterator.next()) |entry| {
        std.debug.print("--- New header found ---\n", .{});
        std.debug.print("\tEntry.name: {s}\n", .{ entry.name });
        std.debug.print("\tEntry.value: {s}\n", .{ entry.value });
        if (std.mem.eql(u8, entry.name, "Cookie")) {
            std.debug.print("Cookie found from browser!\n", .{});
        }
    }
}


//******************************************************************************
// Function: cache_headers
//
// Description:
//******************************************************************************
pub fn get_method(
    self : *const Self
) !std.http.Method {
    if (self.header_method) |method| {
        switch (method) {
            .POST, .GET => {
                return method;
            },
            else => {
                std.log.debug("Unexpected method found: {any}\n", .{ method });
                return error.UnexpectedMethod;
            },
        }
    }
    else {
        std.log.err("Looking for method on request that didn't provide one\n", .{});
        return error.NoMethodPresent;
    }
}
