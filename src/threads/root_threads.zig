//! This module contains all entry points for threads being triggered by main.
//!
//! Its intention is to keep main while still having an organized point to
//! inspect all top level functions are happening. This grouping can be
//! convenient for managing io cancellation instead of searching through all
//! more nuanced modules. 
//!
//! This module is mostly a design decision for a method of trying to keep
//! things clean - it may not be everyone's favorite.
const std = @import("std");
const config = @import("config");
const serverOps = @import("serverOps");
const ComplexStream = @import("complexStream");


//Global const's
const STREAM_BUFF_SIZE : usize = 4096;


//Global Var's
//This variable is the theaded flag... may need to make it volatile or something?
pub var Running : std.atomic.Value(bool) = .init(true);


//##############################################################################
// Struct: Server
//
// Description: This is a local server struct. It allows for try's to check if 
//              the ip address can be initialized. It's really just a handler to
//              get/establish the server based on the config.zap file.
//##############################################################################
pub const Server = struct {
    host : []const u8,
    port : u16,
    addr : std.Io.net.IpAddress,
    io : std.Io,

    //##########################################################################
    // Function:    init
    //
    // Description: This is the constructor for the local Server struct. It
    //              pulls host/port from the already-parsed config and turns
    //              that into an IPv4 address the rest of the thread can bind
    //              with. Fails if the configured address is not valid IPv4.
    //##########################################################################
    pub fn init(io : std.Io) !Server {
        const host: []const u8 = config.get_desired_host();
        const port: u16 = config.get_desired_port();
        const addr = try std.Io.net.IpAddress.parseIp4(host, port);

        return .{ .host = host, .port = port, .addr = addr, .io = io };
    }

    //##########################################################################
    // Function:    listen
    //
    // Description: This function is the actual bind. init only prepares the
    //              address; listen prints that address and starts a TCP
    //              stream listener on it so accept can start handing
    //              connections off to the router threads.
    //##########################################################################
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
// Function:    ctrl_c_override
//
// Description: Function that overrides ctrl+c so threads can be allowed to be 
//              gracefully forced to halt. 
//##############################################################################
pub fn ctrl_c_override(sig: std.c.SIG) callconv(.c) void {
    _ = sig;
    std.debug.print("In custom sig handler...\n", .{});
    Running.store(false, .seq_cst);
}


//##############################################################################
// Function: induce_thread_cancellation
//
// Description: This is a function that is a no frills (sig argument) copy of 
//              the ctrl_c_override. I want the threads of this program to have
//              a mechanism of terminating the WHOLE program when a blocking 
//              issue occurs. This just sets the running variable to false to
//              trigger cancellation of ALL threads in main. 
//##############################################################################
fn induce_thread_cancellation() void {
    Running.store(false, .seq_cst);
}


//##############################################################################
// Function:    accept
//
// Description: Thread that establishes a server, listens for incoming
//              connections, and redirects connection attempts to other threads
//              to optimize concurrency/speed in addressing multiple connections
//
//              The primary directive of this thread is to be the single source
//              of accepting connections, and then handing them off to other
//              threads so other connections can be evalutated on other
//              threads. This should help make the server be as responsive as
//              possbile and limit potential blocking of connections.
//##############################################################################
pub fn accept(
    io : std.Io, 
    queue : *std.Io.Queue(std.Io.net.Stream),
) void {
    //Start thread by creating the server
    const server_struct : Server = Server.init(io) catch |err| {
        std.log.err("-- Server could not be initialized --\n\tThis is IP address related...\n\tError msg: \"{any}\"\n", .{ err });
        induce_thread_cancellation();
        return;
    };
    var server = server_struct.listen() catch |err| {
        std.log.err("-- Server could not be initialized --\n\tThis is related to starting the listner...\n\rError msg: \"{any}\"\n", .{ err });
        return;
    };
    defer server.deinit(io);


    //Server established adding connections to queue for processing.
    while (true) {
        io.checkCancel() catch {
            //std.debug.print("Cancelling accept thread due to top level cancellation\n", .{});
            return;
        };

        //Handle acceptance of a stream.
        if (server.accept(io)) |stream| {
            queue.putOne(io, stream) catch {
                //std.debug.print("Aborting accept thead at queueing due to cancellation...\n", .{});
                return;
            };
        }
        else |err| {
            if (err != error.Canceled) {
                std.debug.print("Error received on connection acceptance in thread: {any}\n", .{ err });
            }
            return;
        }
    }
}


//##############################################################################
// Function:    connection_router
//
// Description: This function is dispersed on as many threads as possible and
//              is the first point of addressing the actual requests received
//              by the server. 
//
//              Connections can/will be routed to other specialized functions, 
//              but this is the first point streams reach after the server's 
//              accept/listen happens.
//##############################################################################
pub fn connection_router(
    allocator : std.mem.Allocator,
    io : std.Io,
    queue : *std.Io.Queue(std.Io.net.Stream),
    thread_num : u8,
) void {
    //std.debug.print("Thread {d} started...\n", .{thread_num});
    while (true) {
        io.checkCancel() catch {
            //std.debug.print("Cancelling accept thread due to top level cancellation\n", .{});
            return;
        };
        //Handle acceptance of a stream.
        if (queue.getOne(io)) |stream| {
            defer stream.close(io);
            std.debug.print("Processing new stream on thread {d}\n", .{ thread_num });

            var buffer_for_reading : [STREAM_BUFF_SIZE]u8 = undefined;
            var buffer_for_writing : [STREAM_BUFF_SIZE]u8 = undefined;

            var complex_stream : ComplexStream = ComplexStream.create(
                stream,
                &buffer_for_reading,
                &buffer_for_writing,
            ) catch |err| {
                std.log.info("Issue establishing stream: {any}\n", .{err});
                continue;
            };

            complex_stream.setup(io) catch |err| {
                std.log.err("Could not setup stream due to error: {any}\n", .{ err });
                continue;
            };

            const continue_interaction = serverOps.authenticated_user_check(io, &complex_stream);
            
            if (continue_interaction) {
                std.log.debug("Should continue connection - valid client", .{});
                serverOps.stream_processing(io, allocator, &complex_stream);
            }
            else {
                std.log.debug("Should not continue request - invalid client (send to login)", .{});
                serverOps.general.send_client_to_login(&complex_stream) catch {
                    @panic("TODO: how do I want to handle failing to redirect?");
                };
            }
        }
        else |_| {
            //std.debug.print("Aborting parsing thead {d} at de-queueing due to cancellation...\n", .{ thread_num });
            return;
        }
    }
}
