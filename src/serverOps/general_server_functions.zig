const std = @import("std");
const ComplexStream = @import("complexStream");

var ConnectionLog : std.ArrayList(ConnectionEntry) = .empty;

const ConnectionEntry = struct {
    ip_addr : std.Io.net.IpAddress,
    camera_name : []const u8,
    last_update : u64,
};

pub fn is_client_recognized_camera(
    complexStream : *ComplexStream
) bool {
    for (ConnectionLog.items) |connectionEntry| {
        const match : bool = std.Io.net.IpAddress.eql(
            &complexStream.stream.socket.address,
            &connectionEntry.ip_addr,
        );
        if (match) return true;
    }
    return false;
}

pub fn send_client_to_login(stream : *ComplexStream) !void {
    try stream.request.respond(
        "",
        .{
            .status = .found,
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "Location", .value = "/login" },
            },
        }
    );
}
