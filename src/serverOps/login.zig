//! Login POST and the two session redirects.
//!
//! This file parses credentials from POST /login, asks `auth` to store a
//! cookie, and redirects home with Set-Cookie. It also sends an
//! unauthenticated client to /login. Cookie/password storage lives in
//! `auth`. The early "may this request proceed?" check is `request_gate.zig`.


const std = @import("std");
const ComplexStream = @import("complexStream");
const auth = @import("auth");


//******************************************************************************
//* Function:    is_login_request
//*
//* Description: True when the target is /login. Used by the request gate
//               (so the login page can load without a session) and by POST
//               routing (so the body is parsed here).
//******************************************************************************
pub fn is_login_request(stream : *const ComplexStream) bool {
    return std.mem.eql(u8, stream.header_target, "/login");
}


//******************************************************************************
//* Function:    manage_attempt
//*
//* Description: This is a function for managing all necessary steps to parse
//               and proceed with a login attempt.
//               It mostly serves as a one-shot that can be called by the
//               generic post logic. 
//
//               This is also just a wrapper around a version of this function
//               that can fail. (This allows downstream use of `try` without 
//               changing ther return value of this functions caller.)
//******************************************************************************
pub fn manage_attempt(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) void {
    manage_attempt_failable(io, allocator, stream) catch |err| {
        std.debug.print("Attempt to mangage login failed due to error: {any}\n", .{ err });
        @panic("TODO: How do I want to handle this login failure");
    };
}


//******************************************************************************
//* Function:    manage_attempt_failable
//*
//* Description: This is the inner implementation of manage_attempt. It parses
//               credentials from the POST body, checks them against auth,
//               issues a new cookie, then redirects the client home.
//
//               It is split out from the wrapper so this path can use `try`
//               without forcing generic_poster to handle an error union.
//               Failures bubble to manage_attempt, which currently panics
//               with a TODO.
//******************************************************************************
fn manage_attempt_failable(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) !void {
    const username, const password = try parse_request(allocator, stream);
    defer {
        allocator.free(username);
        allocator.free(password);
    }
    std.debug.print("The credentials for the stream are:\n", .{});
    std.debug.print("\tUsername: {s}\n", .{ username });
    std.debug.print("\tPassword: {s}\n", .{ password });

    const valid_user = auth.check_user_credential(username, password);
    if (valid_user) {
        std.debug.print("USER IS VALID!\n", .{});
    }
    else {
        std.debug.print("WARNING: User is NOT authorized\n", .{});
    }

    std.log.debug("Starting login function `update_user_cookie`", .{});
    const cookie = try update_user_cookie(io, allocator, username);

    std.log.debug("Ending `update_user_cookie`, starting `send_redirect_to_home`", .{});

    try send_redirect_to_home(stream, cookie);

    std.log.debug("Ending `send_redirect_to_home`", .{});
}


//******************************************************************************
//* Function:    parse_request
//*
//* Description: This function reads the login POST body line-by-line onto
//               the heap so the stream contents can be inspected more than
//               once. After the body is fully copied, extract_creds pulls
//               the username/password pair out of that list.
//
//               The extra copy is more of an insurance method than anything
//               else - particularly in case the stream cannot be rewound.
//               Fails if the stream has no content-length or the body
//               cannot be filled as expected.
//******************************************************************************
fn parse_request(
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) !struct { []const u8, []const u8 } {
    var post_contents : std.ArrayList([]const u8) = .empty;
    defer {
        for (post_contents.items) |line| {
            allocator.free(line);
        }
        post_contents.deinit(allocator);
    }

    var bytes_remaining : u64 = blk: {
        if (stream.content_length) |len| { break :blk len; }
        else { return error.StreamNoContentLen; }
    };

    //Looping through the stream to copy - onto the heap - every line from the
    //POST's login attempt so the credentials can be parsed after making sure
    //all the stream's content has been read. (Adding persistence to the stream
    //to allow analysis)
    while(bytes_remaining > 0) {
        const bytes_to_read = @min(bytes_remaining, 512);
        defer {
            if (bytes_to_read > bytes_remaining) {
                bytes_remaining = 0;
            }
            else {
                bytes_remaining = bytes_remaining - bytes_to_read;
            }
        }
        stream.raw_stream_reader.interface.fill(bytes_to_read) catch return error.BytesToReadMisallignment;
        //defer stream.raw_stream_reader.interface.tossBuffered();

        const foo = stream.raw_stream_reader.interface.buffered();
        var lines = std.mem.splitScalar(u8, foo, '\n');
        while (lines.next()) |line| {
            const duped_line = try allocator.dupe(u8, line);
            try post_contents.append(allocator, duped_line);
            stream.raw_stream_reader.interface.toss(line.len);
        }
    }

    return extract_creds(allocator, &post_contents);
}


//******************************************************************************
//* Function:    extract_creds
//*
//* Description: To allow for the contents of the stream to be read more than
//               once, this function takes an array list with the contents of
//               the stream and parses the credentials from this. The strings
//               for the credentials are allocated for calling functions to be
//               able to have a longer lifetime for computation.
//
//               (more of an insurance method than anything else - particularly
//               in case my structure needs improvement)
//******************************************************************************
fn extract_creds(
    allocator : std.mem.Allocator,
    contents : *std.ArrayList([]const u8),
) !struct { []const u8, []const u8 } {
    for (contents.items) |line| {
        const full_username, const full_password = std.mem.cut(
            u8,
            line,
            "&",
        ) orelse continue;
        _, const username = std.mem.cut(
            u8,
            full_username,
            "=",
        ) orelse continue;
        _, const password = std.mem.cut(
            u8,
            full_password,
            "=",
        ) orelse continue;
        const allocated_username = try allocator.dupe(u8, username);
        const allocated_password = try allocator.dupe(u8, password);
        return .{ allocated_username, allocated_password };
    }
    return error.NoValidCredentialLineFound;
}


//******************************************************************************
//* Function:    update_user_cookie
//*
//* Description: Updating the user database with a new valid cookie that should
//*              be sent to the user to allow subsequent visits without 
//*              revalidation
//******************************************************************************
fn update_user_cookie(
    io : std.Io, 
    allocator : std.mem.Allocator,
    username : []const u8,
) ![]const u8 {
    const now_timestamp = std.Io.Timestamp.now(io, .real);
    const now_nano = now_timestamp.toNanoseconds();
    const seed : u64 = @bitCast(@as(i64, @truncate(now_nano)));
    var xoshiro_rng = std.Random.Xoshiro256.init(seed);
    var random_val : [24]u8 = undefined;
    xoshiro_rng.fill(&random_val);

    for (&random_val) |*char| {
        const interm_char = char.* % 52;
        if (interm_char < 26) {
            char.* = interm_char + 65;
        }
        else {
            char.* = interm_char + 96 - 26;
        }
    }

    const allocated_cookie = try allocator.dupe(u8, &random_val);

    try auth.update_user_cookie(io, username, allocated_cookie);

    return allocated_cookie;
}


//******************************************************************************
//* Function:    send_client_to_login
//*
//* Description: This function sends a 303 redirect to /login with no body.
//               connection_router uses this when authenticated_user_check
//               fails, so the client is pointed at login instead of being
//               left hanging on the resource they asked for.
//******************************************************************************
pub fn send_client_to_login(stream : *ComplexStream) !void {
    try stream.request.respond(
        "",
        .{
            .status = .see_other,
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "Location", .value = "/login" },
            },
        }
    );
}


//******************************************************************************
//* Function:    send_redirect_to_home
//*
//* Description: This function is what actually lands a new session cookie on
//               the client after a successful login. It responds 303 to /
//               and sets session= with HttpOnly, SameSite=Strict, and a
//               short Max-Age.
//
//               The cookie string itself is generated earlier by
//               update_user_cookie; this function only formats the header
//               and sends the redirect.
//******************************************************************************
fn send_redirect_to_home(
    stream : *ComplexStream,
    cookie_string : []const u8,
) !void {
    var backing_buffer_for_cookie_value : [512]u8 = undefined;
    const cookie_value = try std.fmt.bufPrint(
        &backing_buffer_for_cookie_value,
        "session={s}; Path=/; HttpOnly; SameSite=Strict, Max-Age=300",
        .{
            cookie_string,
        },
    );

    std.log.debug("Attempting to respond with redirect to home", .{});
    try stream.request.respond(
        "",
        .{
            .status = .see_other,
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "Location", .value = "/" },
                .{ .name = "Content-Type", .value = "text/html; charset=utf-8" },
                .{ .name = "Set-Cookie",   .value = cookie_value },
            },
        }
    );
    std.log.debug("Sent redirect to home", .{});
}
