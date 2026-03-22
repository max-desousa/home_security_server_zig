const std = @import("std");
const config = @import("config");
const options = @import("options");
const debug = @import("debug");
const threads = @import("threads");


//Global const's
const MAX_THREAD_COUNT = options.max_threads;
const MAX_PARSING_THEADS = MAX_THREAD_COUNT - 2;


//##############################################################################
// Function:    main
//
// Description: 
//##############################################################################
pub fn main() !void {
    //**************************************************************************
    // BEGIN BOILER PLATE (Creating allocators and io)
    //**************************************************************************

    // Create allocator needed for multiple aspects of the program
    var allocator_object : std.heap.DebugAllocator(.{}) = .init;
    defer _ = allocator_object.deinit();
    const allocator = allocator_object.allocator();

    // Create threaded instance with multithreading support
    var threaded : std.Io.Threaded = .init(
        allocator,
        .{ 
            .environ = .empty,
            .concurrent_limit = .limited(MAX_THREAD_COUNT),
        }
    );
    defer threaded.deinit();

    // get io instance.
    const io = threaded.io();

    //**************************************************************************
    // END BOILER PLATE
    //**************************************************************************


    // Set up SIGINT handler for graceful closing
    var action : std.c.Sigaction = .{
        .handler = .{ .handler = threads.ctrl_c_override },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(.INT, &action, null);

    // Reading/establishing config file
    try config.establish_config(io);
    debug.print("Desired Host from config: {s}\n", .{ config.get_desired_host() });

    //Create a server object - done here to simplify error union

    //Create array list of to hold all threads that need to be closed
    //TODO: This array list should be all threads - but I've not developed the thread 
    //for compressing/modifying/appending videos... So - this array list CURRENTLY
    //only has the parsing threads PLUS the accepting thread.
    var threads_to_close : std.ArrayList(std.Io.Future(void)) = try .initCapacity(allocator, (MAX_PARSING_THEADS + 1));

    //Create queue for transferring connections between threads. 
    var buffer_for_streams : [25]std.Io.net.Stream = undefined;
    var queue_for_streams : std.Io.Queue(std.Io.net.Stream) = .init(&buffer_for_streams);

    //Create thread for accepting connections from the server
    const accept_task = try io.concurrent(threads.accept, .{ io, &queue_for_streams });
    try threads_to_close.append(allocator, accept_task);

    //Create threads for operations/parsing accepted connections.
    for (0..MAX_PARSING_THEADS) |i| {
        const task = try io.concurrent(threads.connection_router, .{allocator, io, &queue_for_streams, @intCast(i)});
        try threads_to_close.append(allocator, task);
    }

    //Clean up all threads when program closes
    defer {
        for (threads_to_close.items, 0..) |*future, i| {
            debug.print("Cancelling thread: {d}\n", .{i});
            _ = future.cancel(io);
        }
        debug.print("Deiniting arraylist...\n", .{});
        threads_to_close.deinit(allocator);
    }

    //empty loop to wait for Ctrl+C thanks to sig override.
    while (threads.Running.load(.seq_cst)) {
    }
}
