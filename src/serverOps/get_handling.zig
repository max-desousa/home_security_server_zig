const std = @import("std");
const ComplexStream = @import("complexStream");
const home_page = @import("home_page.zig");
const sysOps = @import("sysOps");
const html = @import("html.zig");

pub fn generic_getter(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) void {
    _ = &allocator;

    std.log.debug("I'm in a getter right now...\n", .{});

    if (sysOps.request_is_directory(io, stream)) {
        html.generate_and_serve_directory_html(io, stream);
    }
    else {
        if (request_is_for_favicon(stream)) {
            std.log.debug("Handling a favicon request\n", .{});
            stream.request.respond(
                "",
                .{
                    .status = .no_content,
                }
            ) catch {
                @panic("TODO: What do I do when server fails to reject favicon");
            };
        }
        else {
            stream.request.respond(
                "",
                .{
                    .status = .not_implemented,
                }
            ) catch {
                @panic("TODO: What do I do when server fails to send \"not implemented\" status code.");
            };
        }
    }
}


fn request_is_for_favicon(stream : *ComplexStream) bool {
    _, const target = std.mem.cutLast(u8, stream.header_target, "/") orelse return false;
    return std.mem.eql(u8, target, "favicon.ico");
}
