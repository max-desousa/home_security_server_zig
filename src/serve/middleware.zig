const std = @import("std");
const Request = @import("request");
const serve = @import("serve.zig");

pub fn all(
    req : *Request,
) !void {
    try discard_favicon_requests(req);
}

fn discard_favicon_requests(
    req : *Request,
) !void {
    if (std.mem.eql(u8, "/favicon.ico", req.req_uri)) {
        try serve.send204(req);
        return error.IgnoreFavicon;
    }
}
