const std = @import("std");
const ComplexStream = @import("complexStream");

pub fn generic_poster(stream : *ComplexStream) void {
    std.debug.print("I'm in a poster right now...\n", .{});
    if (determine_if_video_upload(stream)) {
        std.log.debug("Post request IS video archival\n", .{});
    }
    else {
        std.log.debug("Post request is something other than a video archival\n", .{});
    }
}

fn determine_if_video_upload(stream : *const ComplexStream) bool {
    var header_iterator = stream.http_request.iterateHeaders();

    while (header_iterator.next()) |header| {
        if (std.mem.eql(u8, header.name, "Classification")) {
            return (std.mem.eql(u8, header.value, "Archival"));
        }
    }

    return false;
}
