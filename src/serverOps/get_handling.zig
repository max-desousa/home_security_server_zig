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
            //var file = std.Io.Dir.openFile(.cwd(), io, stream.fs_adjusted_target, .{}) catch |err| {
            //    std.log.err("Could not open file to stream due to: {any}\n", .{ err });
            //    var backing_buffer_for_error_string : [1024]u8 = undefined;
            //    const full_error_string = std.fmt.bufPrint(&backing_buffer_for_error_string, "Could not serve file to client due to client side error \"{any}\" when trying to open the file.", .{ err }) catch |err_string| {
            //        std.log.err("Error creating error string: {any}\n", .{ err_string });
            //        @panic("Look into error in creating error string.");
            //    };
            //    html.send_error_state(stream, full_error_string);
            //    return;
            //};
            var file = std.Io.Dir.openFile(.cwd(), io, "playlist.m3u8", .{}) catch unreachable;
            defer file.close(io);
            html.serve_file_2(io, stream, &file, "application/vnd.apple.mpegurl");
        }
    }
}


fn request_is_for_favicon(stream : *ComplexStream) bool {
    _, const target = std.mem.cutLast(u8, stream.header_target, "/") orelse return false;
    return std.mem.eql(u8, target, "favicon.ico");
}
