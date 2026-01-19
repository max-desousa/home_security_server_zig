const std = @import("std");
const config = @import("config");
const requests = @import("requests");
const serve = @import("serve");

var running : bool = true;
const MAX_CONNECTION_THREAD_COUNT = 4;

pub const Server = struct {
    host : []const u8,
    port : u16,
    addr : std.Io.net.IpAddress,
    io : std.Io,

    pub fn init(io : std.Io) !Server {
        const host: []const u8 = config.get_desired_host();
        const port: u16 = config.get_desired_port();
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

fn interrupt_handler(sig: std.c.SIG) callconv(.c) void {
    _ = sig;
    std.debug.print("In custom sig handler...\n", .{});
    running = false;
}

//##############################################################################
//
// Function: main
//
// Description: 
//
//##############################################################################
pub fn main() !void {

    // Set up SIGINT handler for graceful closing
    var action : std.posix.Sigaction = .{
        .handler = .{ .handler = interrupt_handler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(.INT, &action, null);

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

    var threads_to_close : std.ArrayList(std.Io.Future(anyerror!void)) = try .initCapacity(allocator, MAX_CONNECTION_THREAD_COUNT);

    for (0..MAX_CONNECTION_THREAD_COUNT) |i| {
        const task = try io.concurrent(multi_threaded_handler, .{allocator, io, &server, @intCast(i)});
        try threads_to_close.append(allocator, task);
    }

    defer {
        for (threads_to_close.items, 0..) |*future, i| {
            std.debug.print("Cancelling thread: {d}\n", .{i});
            _ = future.cancel(io) catch {};
        }
        std.debug.print("Deiniting arraylist...\n", .{});
        threads_to_close.deinit(allocator);
    }

    while (running) {
    }
}

fn multi_threaded_handler(
    allocator : std.mem.Allocator,
    io : std.Io,
    server : *std.Io.net.Server,
    thread_num : u8,
) anyerror!void {
    std.debug.print("Thread {d} started...\n", .{thread_num});
    while (true) {
        //Perhaps use this to make sure the thread is canceled on request?
        //std.Io.checkCancel(io) catch return;
        var stream_to_transfer= server.accept(io) catch |err| {
            if (std.Io.Cancelable.Canceled == err) {
                std.debug.print("Cancellation error received at thread: {d}\n", .{thread_num});
                return err;
            }
            std.debug.print("Accept failed: {any}\n", .{err});
            continue;
        };
        std.debug.print("Connection handled by thread: {d}...\n", .{thread_num});
        serve.server_main(allocator, io, &stream_to_transfer) catch |err| {
            if (std.Io.Cancelable.Canceled == err) {
                std.debug.print("Cancellation error received at thread: {d}\n", .{thread_num});
                return err;
            }
            std.debug.print("Accept failed: {any}\n", .{err});
            continue;
        };
        std.debug.print("Request finished for thread: {d}\n", .{thread_num});
    }
}
