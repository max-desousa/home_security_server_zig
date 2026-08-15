const std = @import("std");
const ComplexStream = @import("complexStream");
const auth = @import("auth");

//******************************************************************************
//* Function:    authenticated_user_check
//*
//* Description: This is the early gate used by connection_router before any
//               GET/POST work happens. /login is allowed through so a user
//               can actually submit credentials. Requests that carry a
//               camera hash are also allowed - cameras authenticate
//               differently from a browser session.
//
//               Cookie-bearing requests have to match a cookie this server
//               remembers issuing, and they still have to be inside the
//               server-side expiry window. Client-side cookie expiry is not
//               trusted (browsers are slow to stop sending an expired
//               cookie). Anything else is treated as unauthenticated.
//******************************************************************************
pub fn authenticated_user_check(
    io : std.Io,
    stream : *ComplexStream,
) bool {
    if (std.mem.eql(u8, stream.header_target, "/login")) {
        return true;
    }
    else if (stream.camera_hash) |_| {
        return true;
    }
    else if (stream.cookie_token) |token| {
        std.log.debug("Evaluating cookie: {s}", .{ token });
        if (!auth.is_valid_cookie(token)) return false;

        std.log.debug("Cookie ({s}) was found in arraylist as a valid token", .{ token});

        //if for some reason the expiry time is not present (it should be)
        //eject early
        const expiry_time_for_cookie = auth.cookie_expiry_time(token) orelse return false;

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
    else {
        return false;
    }
}
