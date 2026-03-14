const std = @import("std");
const config = @import("config");
const debug = @import("debug");
const parser = @import("parser");
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
// Function: accept
//
// Description: Thread that establishes a server, listens for incoming
//              connections, and redirects connection attempts to other threads
//              to optimize concurrency/speed in addressing multiple connections
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


//##############################################################################
// Function: connection_router
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

            var buffer_for_reading : [STREAM_BUFF_SIZE]u8 = undefined;
            var buffer_for_writing : [STREAM_BUFF_SIZE]u8 = undefined;

            var complex_stream : ComplexStream = ComplexStream.init(
                io,
                stream,
                &buffer_for_reading,
                &buffer_for_writing,
            ) catch |err| {
                std.log.info("Issue establishing stream: {any}\n", .{err});
                continue;
            };

            const method = complex_stream.get_method() catch |err| {
                std.log.err("Could not find method due to error: {any}\n", .{ err });
                continue;
            };

            switch(method) {
                .GET => parser.get.generic_getter(),
                .POST => parser.post.generic_poster(&complex_stream), 
                else => {
                    std.log.info("Received an unsupported http request (method: {s}) on thread {d}\n", .{ @tagName(method), thread_num });
                },
            }


        //    var buffer_stream_writer : [STREAM_BUFF_SIZE]u8 = undefined;
        //    var buffer_stream_reader : [STREAM_BUFF_SIZE]u8 = undefined;

        //    var stream_reader = stream.reader(io, &buffer_stream_reader);
        //    var stream_writer = stream.writer(io, &buffer_stream_writer);

        //    var http_server : std.http.Server = .init(&stream_reader.interface, &stream_writer.interface);
        //    var http_request = http_server.receiveHead() catch |err| {
        //        std.debug.print("Error processing http_request in parsing thread: {any}\n", .{ err });
        //        continue;
        //    };

        //    print_http_req_header(&http_request.head);
        //    const save_info = get_save_info(&http_request);

        //    var buffer_for_reader : [4096]u8 = std.mem.zeroes([4096]u8);
        //    var buffer_for_writer : [4096]u8 = std.mem.zeroes([4096]u8);
        //    var alt_stream_reader = http_request.readerExpectNone(&buffer_for_reader);

        //    const new_file = try std.Io.Dir.createFile(.cwd(), io, "test.ts", .{});
        //    var new_file_writer = std.Io.File.writer(new_file, io, &buffer_for_writer);

        //    while (alt_stream_reader.fillMore()) {
        //        _ = try new_file_writer.interface.write(alt_stream_reader.buffered());
        //        alt_stream_reader.tossBuffered();
        //    }
        //    else |err| {
        //        if (error.EndOfStream != err) {
        //            return err;
        //        }
        //    }

        //    unreachable;
        }
        else |_| {
            std.debug.print("Aborting parsing thead {d} at de-queueing due to cancellation...\n", .{ thread_num });
            return;
        }
    }
}
