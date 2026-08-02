//! This is a file with server functions specifically for handling matters related to login process. 
//!
//! Things that will for sure be here:
//!   - Parsing data from stream to assess credentials
//!   - Sending different responses based on the validity of the credentials


const std = @import("std");
const ComplexStream = @import("complexStream");
const config = @import("config");


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
//* Function:    manage_attempt
//*
//* Description: This is a function for managing all necessary steps to parse
//               and proceed with a login attempt.
//               It mostly serves as a one-shot that can be called by the
//               generic post logic. 
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

    const valid_user = config.check_user_credential(username, password);
    if (valid_user) {
        std.debug.print("USER IS VALID!\n", .{});
    }
    else {
        std.debug.print("WARNING: User is NOT authorized\n", .{});
    }

    update_user_cookie(io, username);
}


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
//               be sent to the user to allow subsequent visits without 
//               revalidation
//******************************************************************************
fn update_user_cookie(
    io : std.Io, 
    username : []const u8,
) void {
    const now_timestamp = std.Io.Timestamp.now(io, .real);
    const now_nano = now_timestamp.toNanoseconds();
    const seed : u64 = @bitCast(@as(i64, @truncate(now_nano)));
    var xoshiro_rng = std.Random.Xoshiro256.init(seed);
    var random_val : [24]u8 = undefined;
    xoshiro_rng.fill(&random_val);

    std.debug.print("Random cookie: {s}\n", .{ random_val });
    for (&random_val) |*char| {
        std.debug.print("\told char val: {c}", .{ char.* });
        const interm_char = char.* % 52;
        if (interm_char < 26) {
            char.* = interm_char + 65;
        }
        else {
            char.* = interm_char + 96;
        }
        std.debug.print("\t/\tnew char val: {c}\n", .{ char.* });
    }
    std.debug.print("Random cookie: {s}\n", .{ random_val });

    _ = &username;
}
