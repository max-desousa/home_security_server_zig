const std = @import("std");
const ComplexStream = @import("complexStream");
const archive_payload = @import("archive.zig").archive_payload;

pub fn special_camera_upload(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) !void {
    var buffer_for_nonce_string : [64]u8 = undefined;
    const nonce : u64 = undefined;

    const string_nonce = try std.fmt.bufPrint(&buffer_for_nonce_string, "{d}", .{ nonce });

    try stream.request.respond(
        "", 
        .{
            .status = .ok,
            .keep_alive = true,
            .extra_headers = &.{
                .{ .name = "nonce", .value = string_nonce },
            },
        });

    const req = try stream.request.server.receiveHead();

    var header_iterator = req.iterateHeaders();

    const submitted_tag : []const u8 = blk: {
        while (header_iterator.next()) |header| {
            if (std.mem.eql(u8, "Camera-Tag", header.name)) {
                break :blk header.value;
            }
        }
        return error.NoTagReceivedFromCamera;
    };

    if (!compare_tag(submitted_tag)) {
        try stream.request.respond(
            "", 
            .{
                .status = .unauthorized,
                .keep_alive = false,
            });
        return;
    }

    try stream.request.respond(
        "", 
        .{
            .status = .ok,
            .keep_alive = true,
        });

    archive_payload(allocator, io, stream);

    return error.NotYetImplemented;
}

fn compare_tag(tag : []const u8) bool {
    _ = &tag;
    @panic("Not yet implemented");
}
