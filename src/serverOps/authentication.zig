const std = @import("std");
const ComplexStream = @import("complexStream");

pub fn authenticated_user_check(
    stream : *ComplexStream,
) bool {
    if (stream.camera_hash) |_| {
        return true;
    }
    else if (stream.cookie_token) |token| {
        _ = &token;
        return false;
    }
    else {
        return false;
    }
}
