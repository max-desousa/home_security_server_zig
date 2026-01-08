const std = @import("std");
const config = @import("config");
const requests = @import("requests");


pub const Server = struct {
    host : []const u8,
    port : u16,
    addr : std.Io.net.IpAddress,
    io : std.Io,

    pub fn init(io : std.Io) !Server {
        const host: []const u8 = "127.0.0.1";
        const port: u16 = 3490;
        const addr = try std.Io.net.IpAddress.parseIp4(host, port);

        return .{ .host = host, .port = port, .addr = addr, .io = io };
    }

    pub fn listen(self: Server) !std.Io.net.Server {
        std.debug.print("Server Addr: {s}:{any}\n", .{self.host, self.port});
        return try self.addr.listen(
            self.io, 
            .{
                .mode = .stream,
                .protocol = .tcp,
            }
        );
    }
};


//##############################################################################
//
// Function: 
//
// Description: 
//
//##############################################################################
fn handle_connection(
    allocator : std.mem.Allocator,
    io : std.Io, 
    stream : *std.Io.net.Stream, 
) void {
    defer stream.close(io);

    requests.parse_and_serve_req_path(allocator, io, stream) catch |err| {
        std.debug.print("Top level failure: {any}\n", .{err});
        return;
    };
}


//##############################################################################
//
// Function: main
//
// Description: 
//
//##############################################################################
pub fn main() !void {
    // Create allocator needed for multiple aspects of the program
    var allocator_object : std.heap.DebugAllocator(.{}) = .init;
    defer _ = allocator_object.deinit();
    const allocator = allocator_object.allocator();

    // Create threaded instance with multithreading support
    var threaded : std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    // get io instance.
    const io = threaded.io();

    // END BOILER PLATE

    try config.establish_config(io);
    std.debug.print("Desired Host from config: {s}\n", .{config.get_desired_host()});

    const server_struct : Server = try .init(io);
    var server = try server_struct.listen();
    defer server.deinit(io);

    while (true) {
        var stream_to_transfer = server.accept(io) catch |err| {
            std.debug.print("Accept failed: {any}\n", .{err});
            continue;
        };

        _ = io.async(handle_connection, .{allocator, io, &stream_to_transfer});
    }
}
