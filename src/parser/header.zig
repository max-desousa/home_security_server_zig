const std = @import("std");
const debug = @import("debug");

fn print_http_req_header(
    req : *std.http.Server.Request.Head,
) void {
    debug.print("\tMethod: {any}\n", .{ req.method });
    debug.print("\tTarget: {s}\n", .{ req.target });
    debug.print("\tVersion: {any}\n", .{ req.version });

    debug.print("\tExpect: ", .{});
    if (req.expect) |expect| {
        debug.print("{s}\n", .{ expect });
    }
    else {
        debug.print("- None present\n", .{});
    }

    debug.print("\tContent-Type: ", .{});
    if (req.content_type) |content_type| {
        debug.print("{s}\n", .{ content_type });
    }
    else {
        debug.print("- None present\n", .{});
    }

    debug.print("\tContent-Length: ", .{});
    if (req.content_length) |content_length| {
        debug.print("{d}\n", .{ content_length });
    }
    else {
        debug.print("- None present\n", .{});
    }

    debug.print("\tTransfer-Encoding: {any}\n", .{ req.transfer_encoding });
    debug.print("\tTransfer-Compression: {any}\n", .{ req.transfer_compression });
    debug.print("\tKeep-Alive: {any}\n", .{ req.keep_alive });
}

fn get_file_save_location(
    allocator : std.mem.Allocator,
    request : *std.http.Server.Request,
) ![]const u8 {
    return try std.mem.Allocator.dupe(allocator, u8, request.head.target);
}

fn get_save_file_name(
    allocator : std.mem.Allocator,
    request : *std.http.Server.Request,
) ![]const u8 {
    var header_iterator = request.iterateHeaders();
    while (header_iterator.next()) |header| {
        if (std.mem.eql(header.name, "File Name")) {
            return try std.fmt.allocPrint(allocator, "{s}", header.value);
        }
    }
}

fn print_iterated_headers(
    request : *std.http.Server.Request,
) void {
    var header_iterator = request.iterateHeaders();
    debug.print("*********************************\n", .{});
    debug.print("PRINTING HEADERS FROM ITERATOR:\n", .{});
    while (header_iterator.next()) |header| {
        debug.print("\tName: {s}\n\tValue: {s}\n\n", .{header.name, header.value});
    }
    debug.print("DONE WITH HEADER ITERATOR\n", .{});
    debug.print("*********************************\n", .{});
}
