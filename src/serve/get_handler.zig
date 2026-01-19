const std = @import("std");
const Request = @import("request");
const serve = @import("serve.zig");

pub fn run(req : *Request) !void {
    std.debug.print("We're in the get handler...\n", .{});
    std.debug.print("We are in the get handler, handling a GET of \"{s}\"\n", .{req.req_uri});
    const nullable_file = try determine_if_requesting_static_html(req);
    var file = nullable_file orelse unreachable;
    defer file.close(req.io);
    try serve.serve_successful_static_file(req.io, file, req.stream);
}

fn determine_if_requesting_static_html(req : *Request) !?std.Io.File {
    return try find_static_file(req.io, req.req_uri);
}

fn find_static_file(io : std.Io, sub_path : []const u8) !?std.Io.File {
    var buffer_for_modified_path : [1024]u8 = std.mem.zeroes([1024]u8);
    const modified_path = try std.fmt.bufPrint(&buffer_for_modified_path, "static/{s}.html", .{sub_path});

    return std.Io.Dir.openFile(std.Io.Dir.cwd(), io, modified_path, .{}) catch |err| {
        if (std.Io.File.OpenError.FileNotFound == err) {
            return null;
        }
        return err;
    };
}
