const std = @import("std");
const ComplexStream = @import("complexStream");

pub fn authenticated_user_check(
    stream : *ComplexStream,
) bool {
    if (stream.camera_hash) |_| {
        return true;
    }
    else if (stream.cookie_token) |token| {
        //Checking if token is a valid cookie
        _ = &token;
        return true;
    }
    else if (std.mem.eql(u8, stream.header_target, "/login")) {
        return true;
    }
    else {
        return false;
    }
}
