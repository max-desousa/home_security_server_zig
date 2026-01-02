const std = @import("std");
const config = @import("config");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // Create allocator needed for multiple aspects of the program
    var allocator_object : std.heap.DebugAllocator(.{}) = .init;
    defer _ = allocator_object.deinit();
    const allocator = allocator_object.allocator();

    // Create threaded instance with multithreading support
    var threaded : std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    // get io instance.
    const io = threaded.io();

    try config.establish_config(io);
    std.debug.print("Desired Host from config: {s}\n", .{config.get_desired_host()});
}

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
