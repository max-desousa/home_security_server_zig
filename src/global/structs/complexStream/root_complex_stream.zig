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

content_length : ?u64 = null,

//We need a field to parse the header and store the user's cookies (and the allocator that will enable storage)
allocator : std.mem.Allocator,
cookie_token : ?[]u8 = null,
camera_hash : ?[]u8 = null,

backing_buffer_for_fs_adjusted_target : [BUFFER_SIZE_FOR_HEADER_FIELDS]u8 = std.mem.zeroes([BUFFER_SIZE_FOR_HEADER_FIELDS]u8),
fs_adjusted_target : []u8 = undefined,


//------------------------------ BEGIN METHODS ---------------------------------


pub fn create(
    stream : std.Io.net.Stream,
    allocator : std.mem.Allocator,
    buffer_for_reading : []u8,
    buffer_for_writing : []u8,
) !Self {
    return .{
        .stream = stream,
        .allocator = allocator,
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

pub fn deinit(
    self : *Self,
) void {
    if (self.cookie_token) |slice| {
        self.allocator.free(slice);
    }
    if (self.camera_hash) |slice| {
        self.allocator.free(slice);
    }
}


//******************************************************************************
// Function: cache_headers
//
// Description:
//******************************************************************************
fn cache_headers(self : *Self) !void {
    self.request = try self.server.receiveHead();

    // Caching content length
    if (self.request.head.content_length) |len| {
        self.content_length = len;
    }

    //Cacing method of the connection
    self.header_method = self.request.head.method;

    //Caching a target string that matches the file system
    //    -> a login of '/' correlates to '.' in the filesystem
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

    //Here we itterate and allocate any additional headers
    var headerIterator = self.request.iterateHeaders();
    while (headerIterator.next()) |entry| {
        if (std.mem.eql(u8, entry.name, "Cookie")) {
            const allocated_cookie_token = try self.allocator.dupe(u8, entry.value);
            self.cookie_token = allocated_cookie_token;
        }
        if (std.mem.eql(u8, entry.name , "Camera-Hash")) {
            const allocated_camera_hash = try self.allocator.dupe(u8, entry.value);
            self.camera_hash = allocated_camera_hash;
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
