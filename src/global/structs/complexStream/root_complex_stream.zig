const std = @import("std");

const Self = @This();

const BUFFER_SIZE_FOR_HEADER_FIELDS = 512;

//##############################################################################
//######################### Fields and Descriptions ############################
//##############################################################################

//----------------------- Begin must provide fields...--------------------------

// Underlying (backing) stream. This is used primarly just for securing the
// readers/writers, but its use afterwards it mostly non-existent. Not sure if
// it could be deleted... leaving for now.
stream : std.Io.net.Stream,

// In order to interact with the stream, there need to be readers and writers.
// These are provided with the creation of the struct to make sure the
// lifetimes of the buffers match the lifetime of the parent.
backing_buffer_for_raw_stream_writer : []u8,
backing_buffer_for_raw_stream_reader : []u8,


//---------------------- Begin Infrastructure fields... ------------------------

// What do we mean by infrastructure fields - fields that are likely not
// interacted with for any reason. They are not private due to the language -
// but the general expectation is that these would not be interacted with.

// Necessary elements for zig's server parsing - sever needs a reader and writer
// zig's library to help with http parsing needs the std.Io.net.Stream's reader
// and writer to enable handling parsing and responding... but these should not
// be touched... they are BACKING writers... hidden under a few layers writing 
// the raw bitstreams... not the ease of access in handling http compliance...
// that's another set of readers/writers. 
raw_stream_reader : std.Io.net.Stream.Reader = undefined,
raw_stream_writer : std.Io.net.Stream.Writer = undefined,

// The "server" object that we'll reference when parsing the body etc (backed by the stream readers and writers)
server : std.http.Server = undefined,
// A convenient way - for now of caching data related to the initial stream.
// Most of the useful information is duplicated in subsequent fields for
// cleaner accessing.
request : std.http.Server.Request = undefined,


//------------------------- Begin Useable fields... ----------------------------

// Usable meaning public (essentially)

// Fields to cache all necessary header information necessary
// (The state of reading the headers seems transient - so we have greater success
// parsing everything immediately)

// This is the mechanism to store the requested target in the stream. This will
// be a direct copy
backing_buffer_for_target : [BUFFER_SIZE_FOR_HEADER_FIELDS]u8 = std.mem.zeroes([BUFFER_SIZE_FOR_HEADER_FIELDS]u8),
header_target : []u8 = undefined,

// This effectively conveys the same information has header_target and it's
// backing buffer but is offered as a conveninece field. Much of this
// application - currently assumes serving a local file system or directory.
// This modifies the string from header target so this string can be treated as
// a file path that works with the stdlib.
backing_buffer_for_fs_adjusted_target : [BUFFER_SIZE_FOR_HEADER_FIELDS]u8 = std.mem.zeroes([BUFFER_SIZE_FOR_HEADER_FIELDS]u8),
fs_adjusted_target : []u8 = undefined,

// At the start of development we had some funky behavior (probably user error)
// in referring to the request field. It wasn't clear if that value was lost as
// the stream was being passed to different functions. This field was created
// to store the most valuable field in stream - the method - for functions to
// reference
header_method : ?std.http.Method = null,

// Self explanatory - this is for the user to populate
content_length : ?u64 = null,

//--------------------------- Begin Header Fields ------------------------------

// What are these fields? This was another aspect related to the uncertainty of
// behavior of the request field. It did not seem possible to iterate over
// headers and what not after the stream started getting processed - which
// could easily make sense. These fields are backing buffers and slices for
// storing strings of pertinent headers that are being scanned when a stream is
// incoming. That way they are persistent for the lifetime of the parent

// Cookies - self explanatory
backing_buffer_for_cookie : [BUFFER_SIZE_FOR_HEADER_FIELDS]u8 = undefined,
cookie_token : ?[]u8 = null,


//------------------------------ BEGIN METHODS ---------------------------------


//******************************************************************************
//* Function:    create
//*
//* Description: This is the constructor for ComplexStream. It stores the raw
//               std.Io.net.Stream and the caller-owned read/write buffers so
//               later setup can wire Zig's HTTP server objects without the
//               caller having to know those internals.
//
//               This does not touch the network. setup is the follow-up that
//               actually attaches readers/writers and caches the request
//               head.
//******************************************************************************
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

//******************************************************************************
//* Function:    setup
//*
//* Description: This function wires the raw reader/writer onto the stored
//               stream, constructs the std.http.Server over those, then
//               immediately calls cache_headers.
//
//               The header-caching step is intentional. Later routing wants
//               header_target, cookies, camera hash, etc. without trying to
//               re-read a head that has already been consumed.
//******************************************************************************
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
//* Function:    cache_headers
//*
//* Description: This function receives the HTTP head once and copies out
//               everything this server later needs: content-length, method,
//               the raw target, a filesystem-adjusted target ("/" becomes
//               "."), the session= cookie token, and an optional Camera-Hash.
//
//               Header state from Zig's server looks transient, so this has
//               to happen immediately in setup. After this, routing should
//               be able to work from the cached fields alone.
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
            std.log.debug("The cookie token in the stream is: {s}", .{ entry.value });

            var working_slice_for_cookie = entry.value;

            if (std.mem.containsAtLeast(u8, entry.value, 1, "session=")) {
                _, working_slice_for_cookie = std.mem.cut(u8, entry.value, "session=") orelse return error.InvalidCookieNoSessionString;
            }

            if (std.mem.containsAtLeast(u8, entry.value, 1, ";")) {
                working_slice_for_cookie, _ = std.mem.cut(u8, working_slice_for_cookie, ";") orelse return error.InvalidCookieSemiColon;
            }

            const len = working_slice_for_cookie.len;
            @memcpy(self.backing_buffer_for_cookie[0..len], working_slice_for_cookie);
            self.cookie_token = self.backing_buffer_for_cookie[0..len];
        }
    }
}


//******************************************************************************
//* Function:    get_method
//*
//* Description: This function returns the method that was cached during
//               setup. Only GET and POST are treated as supported so
//               unsupported verbs never reach the GET/POST routers.
//
//               A missing method, or any method other than GET/POST, is
//               returned as an error for the caller to log and drop.
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
