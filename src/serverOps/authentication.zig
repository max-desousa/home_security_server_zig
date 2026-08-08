const std = @import("std");
const config = @import("config");
const ComplexStream = @import("complexStream");

pub fn authenticated_user_check(
    io : std.Io,
    stream : *ComplexStream,
) bool {
    if (stream.camera_hash) |_| {
        return true;
    }
    else if (stream.cookie_token) |token| {
        if (!config.is_valid_cookie(token)) return false;

        const expiry_time_for_cookie = config.cookie_expiry_time(token);

        //Getting current time to check against our saved cookie data
        const timestamp_now = std.Io.Timestamp.now(io, .real);
        const now_seconds = timestamp_now.toSeconds();
        
        //Is the current time greater than the expiry time for the cookie?
        if (now_seconds >= expiry_time_for_cookie) {
            return false;
        }

        //No checks that would invalidate the requests present cookie... return
        //true to indicate server can keep proceeding.
        return true;
    }
    else if (std.mem.eql(u8, stream.header_target, "/login")) {
        return true;
    }
    else {
        return false;
    }
}
