//! Early request gate: may this request proceed to GET/POST work?
//!
//! `/login` and camera-hash requests are allowed through. Cookie-bearing
//! requests are checked against the `auth` store and the server-side expiry
//! window. This is not the credential store (`auth`) and not the login POST
//! (`login.zig`).

const std = @import("std");
const ComplexStream = @import("complexStream");
const auth = @import("auth");
const login = @import("login.zig");

pub const ConnectionType = enum {
    HumanClientLoginReq,
    PotentialCameraBeginningHandshake,
    CachedUser,
    TimedOutUser,
    InvalidConnectionAttempt,
    InvalidCookie,
    InvalidCookieDataInDatabase,
};

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
) ConnectionType {
    if (login.is_login_request(stream)) {
        return .HumanClientLoginReq;
    }
    else if (is_camera_handshake_starter(stream)) {
        return .PotentialCameraBeginningHandshake;
    }
    else if (stream.cookie_token) |token| {
        std.log.debug("Evaluating cookie: {s}", .{ token });
        if (!auth.is_valid_cookie(token)) return .InvalidCookie;

        std.log.debug("Cookie ({s}) was found in arraylist as a valid token", .{ token});

        //if for some reason the expiry time is not present (it should be)
        //eject early
        const expiry_time_for_cookie = auth.cookie_expiry_time(token) orelse return .InvalidCookieDataInDatabase;

        //Getting current time to check against our saved cookie data
        const timestamp_now = std.Io.Timestamp.now(io, .real);
        const now_seconds = timestamp_now.toSeconds();

        //Is the current time greater than the expiry time for the cookie?
        if (now_seconds >= expiry_time_for_cookie) {
            return .TimedOutUser;
        }

        //No checks that would invalidate the requests present cookie... return
        //true to indicate server can keep proceeding.
        return .CachedUser;
    }
    else {
        return .InvalidConnectionAttempt;
    }
}


fn is_camera_handshake_starter(stream : *const ComplexStream) bool {
    return std.mem.eql(u8, stream.header_target, "/bch");
}
