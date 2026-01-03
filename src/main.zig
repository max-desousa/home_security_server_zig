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

    // END BOILER PLATE

    //Open Hello world file for reading. 
    const source_file = try std.Io.Dir.openFile(
        std.Io.Dir.cwd(),
        io,
        "static/HelloWorld.html",
        .{}
    );
    defer source_file.close(io);

    //Open and read hello world html into heap buffer.
    var buffer_file_reader : [1024]u8 = std.mem.zeroes([1024]u8);
    var file_reader_full = source_file.reader(io, &buffer_file_reader);
    var file_reader = &file_reader_full.interface;
    const hello_world_data = try file_reader.readAlloc(allocator, try source_file.length(io));
    defer allocator.free(hello_world_data);

    try config.establish_config(io);
    std.debug.print("Desired Host from config: {s}\n", .{config.get_desired_host()});

    const server_struct : Server = try .init(io);
    var server = try server_struct.listen();
    defer server.deinit(io);

    while (true) {
        const stream = server.accept(io) catch |err| {
            std.debug.print("Accept failed: {any}\n", .{err});
            continue;
        };

        _ = io.async(handle_connection, .{io, stream, hello_world_data});
    }


}

fn handle_connection(io : std.Io, stream : std.Io.net.Stream, data_to_write : []u8) void {
    defer stream.close(io);

    var buffer_for_writer : [1024]u8 = std.mem.zeroes([1024]u8);
    var stream_writer = stream.writer(io, &buffer_for_writer);
    defer stream_writer.interface.flush() catch {};

    const response_header = 
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/html; charset=UTF-8\r\n" ++
        "Content-Length: 218\r\n" ++
        "Connection: close\r\n" ++
        "\r\n";

    stream_writer.interface.writeAll(response_header) catch {
        std.debug.print("Error writing response header\n", .{});
        return;
    };
    stream_writer.interface.writeAll(data_to_write) catch {
        std.debug.print("Error writing response\n", .{});
        return;
    };
    stream_writer.interface.flush() catch {
        std.debug.print("Error flushing header\n", .{});
        return;
    };
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
