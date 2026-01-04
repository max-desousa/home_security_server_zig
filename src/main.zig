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

    //##########################################################################
    //const page_served = requests.serve_page_if_requested(allocator, io, stream) catch |err| {
    //    std.debug.print("There was an error addressing the stream: {any}\n", .{err});
    //    return;
    //};
    //if (page_served) return;

    //requests.send404(io, stream);
    //##########################################################################

    //const nullable_read = try requests.get_request_msg(allocator, io, stream);
    //const read = nullable_read orelse {
    //    std.debug.print("Request was not a GET\n", .{});
    //    continue;
    //};
    //defer allocator.free(read);


    //var buffer_for_reader : [1024]u8 = std.mem.zeroes([1024]u8);
    //var stream_reader = stream.reader(io, &buffer_for_reader);

    //std.debug.print("Start of data from client...\n", .{});
    ////while (stream_reader.interface.takeDelimiterInclusive('\n')) |nullable_line| {
    //while (stream_reader.interface.takeDelimiterInclusive('\n')) |line| {
    //    if (std.mem.eql(u8, line, "\r\n")) break;
    //    std.debug.print("{s}", .{line});
    //} else |err| {
    //    if (error.EndOfStream != err) {
    //        std.debug.print("Error reading stream: {any}\n", .{err});
    //    }
    //}
    //std.debug.print("End of data from client...\n", .{});


    //var buffer_for_writer : [1024]u8 = std.mem.zeroes([1024]u8);
    //var stream_writer = stream.writer(io, &buffer_for_writer);
    //defer stream_writer.interface.flush() catch {};

    //const response_header = 
    //    "HTTP/1.1 200 OK\r\n" ++
    //    "Content-Type: text/html; charset=UTF-8\r\n" ++
    //    "Content-Length: 218\r\n" ++
    //    "Connection: close\r\n" ++
    //    "\r\n";

    //stream_writer.interface.writeAll(response_header) catch {
    //    std.debug.print("Error writing response header\n", .{});
    //    return;
    //};
    //stream_writer.interface.writeAll(data_to_write) catch {
    //    std.debug.print("Error writing response\n", .{});
    //    return;
    //};
    //stream_writer.interface.flush() catch {
    //    std.debug.print("Error flushing header\n", .{});
    //    return;
    //};
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
