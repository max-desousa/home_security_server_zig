const std = @import("std");
const config = @import("config");
const requests = @import("requests");
const serve = @import("serve");
const options = @import("options");

var running : bool = true;
const MAX_THREAD_COUNT = options.max_threads;
const MAX_PARSING_THEADS = MAX_THREAD_COUNT - 2;
const STREAM_BUFF_SIZE : usize = 4096;

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
    var action : std.c.Sigaction = .{
        .handler = .{ .handler = interrupt_handler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(.INT, &action, null);

    //**************************************************************************
    // BEGIN BOILER PLATE
    //**************************************************************************
    //
    // Create allocator needed for multiple aspects of the program
    var allocator_object : std.heap.DebugAllocator(.{}) = .init;
    defer _ = allocator_object.deinit();
    const allocator = allocator_object.allocator();

    // Create threaded instance with multithreading support
    var threaded : std.Io.Threaded = .init(allocator, .{ .environ = .empty });
    defer threaded.deinit();

    // get io instance.
    const io = threaded.io();

    //**************************************************************************
    // END BOILER PLATE
    //**************************************************************************

    // Reading/establishing config file
    try config.establish_config(io);
    std.debug.print("Desired Host from config: {s}\n", .{config.get_desired_host()});

    //Create a server object
    const server_struct : Server = try .init(io);
    var server = try server_struct.listen();
    defer server.deinit(io);

    //Create array list of to hold all threads that need to be closed
    //TODO: This array list should be all threads - but I've not developed the thread 
    //for compressing/modifying/appending videos... So - this array list CURRENTLY
    //only has the parsing threads PLUS the accepting thread.
    var threads_to_close : std.ArrayList(std.Io.Future(anyerror!void)) = try .initCapacity(allocator, (MAX_PARSING_THEADS + 1));

    //Create queue for transferring connections between threads. 
    var buffer_for_streams : [25]std.Io.net.Stream = undefined;
    var queue_for_streams : std.Io.Queue(std.Io.net.Stream) = .init(&buffer_for_streams);

    //Create thread for accepting connections from the server
    const accept_task = try io.concurrent(accept_thread, .{ io, &server, &queue_for_streams });
    try threads_to_close.append(allocator, accept_task);

    //Create threads for operations/parsing accepted connections.
    for (0..MAX_PARSING_THEADS) |i| {
        const task = try io.concurrent(multi_threaded_handler, .{allocator, io, &queue_for_streams, @intCast(i)});
        try threads_to_close.append(allocator, task);
    }

    //Clean up all threads when program closes
    defer {
        for (threads_to_close.items, 0..) |*future, i| {
            std.debug.print("Cancelling thread: {d}\n", .{i});
            _ = future.cancel(io) catch {};
        }
        std.debug.print("Deiniting arraylist...\n", .{});
        threads_to_close.deinit(allocator);
    }

    //empty loop to wait for Ctrl+C thanks to sig override.
    while (running) {
    }
}


fn accept_thread(
    io : std.Io, 
    server : *std.Io.net.Server,
    queue : *std.Io.Queue(std.Io.net.Stream),
) anyerror!void {
    while (true) {
        io.checkCancel() catch {
            std.debug.print("Cancelling accept thread due to top level cancellation\n", .{});
            return;
        };

        //Handle acceptance of a stream.
        if (server.accept(io)) |stream| {
            queue.putOne(io, stream) catch {
                std.debug.print("Aborting accept thead at queueing due to cancellation...\n", .{});
                return;
            };
        }
        else |err| {
            std.debug.print("Error received on connection acceptance in thread: {any}\n", .{ err });
            return;
        }
    }
}

fn multi_threaded_handler(
    allocator : std.mem.Allocator,
    io : std.Io,
    queue : *std.Io.Queue(std.Io.net.Stream),
    thread_num : u8,
) anyerror!void {
    _ = &allocator;
    std.debug.print("Thread {d} started...\n", .{thread_num});
    while (true) {
        io.checkCancel() catch {
            std.debug.print("Cancelling accept thread due to top level cancellation\n", .{});
            return;
        };
        //Handle acceptance of a stream.
        if (queue.getOne(io)) |stream| {
            std.debug.print("Processing new stream on thread {d}\n", .{ thread_num });
            var buffer_stream_writer : [STREAM_BUFF_SIZE]u8 = undefined;
            var buffer_stream_reader : [STREAM_BUFF_SIZE]u8 = undefined;

            var stream_reader = stream.reader(io, &buffer_stream_reader);
            var stream_writer = stream.writer(io, &buffer_stream_writer);

            var http_server : std.http.Server = .init(&stream_reader.interface, &stream_writer.interface);
            var http_request = http_server.receiveHead() catch |err| {
                std.debug.print("Error processing http_request in parsing thread: {any}\n", .{ err });
                continue;
            };

            print_http_req_header(&http_request.head);
        }
        else |_| {
            std.debug.print("Aborting parsing thead {d} at de-queueing due to cancellation...\n", .{ thread_num });
            return;
        }
    }
    //while (true) {
    //    //Perhaps use this to make sure the thread is canceled on request?
    //    //std.Io.checkCancel(io) catch return;
    //    var stream_to_transfer = server.accept(io) catch |err| {
    //        if (std.Io.Cancelable.Canceled == err) {
    //            std.debug.print("Cancellation error received at thread: {d}\n", .{thread_num});
    //            return err;
    //        }
    //        std.debug.print("Accept failed: {any}\n", .{err});
    //        continue;
    //    };
    //    defer stream_to_transfer.close(io);
    //    std.debug.print("Connection handled by thread: {d}...\n", .{thread_num});

    //    var buffer_stream_writer : [BUFF_SIZE]u8 = undefined;
    //    var buffer_stream_reader : [BUFF_SIZE]u8 = undefined;

    //    var stream_reader = stream_to_transfer.reader(io, &buffer_stream_reader);
    //    var stream_writer = stream_to_transfer.writer(io, &buffer_stream_writer);

    //    var http_server : std.http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    //    _ = &allocator;
    //    const http_request = try http_server.receiveHead();
    //    std.debug.print("HTTP metod received = {any}\n", .{ http_request.head.method });
    //    std.debug.print("HTTP version received = {any}\n", .{ http_request.head.version });
    //    if (http_request.head.content_length) |length| {
    //        std.debug.print("Length found of: {d}...\n", .{length});
    //    }
    //    else {
    //        std.debug.print("No (null) length found...\n", .{});
    //    }

    //    //serve.server_main(allocator, io, &stream_to_transfer) catch |err| {
    //    //    if (std.Io.Cancelable.Canceled == err) {
    //    //        std.debug.print("Cancellation error received at thread: {d}\n", .{thread_num});
    //    //        return err;
    //    //    }
    //    //    std.debug.print("Accept failed: {any}\n", .{err});
    //    //    continue;
    //    //};
    //    //std.debug.print("Request finished for thread: {d}\n", .{thread_num});
    //}
}


fn print_http_req_header(
    req : *std.http.Server.Request.Head,
) void {
    std.debug.print("\tMethod: {any}\n", .{ req.method });
    std.debug.print("\tTarget: {s}\n", .{ req.target });
    std.debug.print("\tVersion: {any}\n", .{ req.version });

    std.debug.print("\tExpect: ", .{});
    if (req.expect) |expect| {
        std.debug.print("{s}\n", .{ expect });
    }
    else {
        std.debug.print("- None present\n", .{});
    }

    std.debug.print("\tContent-Type: ", .{});
    if (req.content_type) |content_type| {
        std.debug.print("{s}\n", .{ content_type });
    }
    else {
        std.debug.print("- None present\n", .{});
    }

    std.debug.print("\tContent-Length: ", .{});
    if (req.content_length) |content_length| {
        std.debug.print("{d}\n", .{ content_length });
    }
    else {
        std.debug.print("- None present\n", .{});
    }

    std.debug.print("\tTransfer-Encoding: {any}\n", .{ req.transfer_encoding });
    std.debug.print("\tTransfer-Compression: {any}\n", .{ req.transfer_compression });
    std.debug.print("\tKeep-Alive: {any}\n", .{ req.keep_alive });
}
