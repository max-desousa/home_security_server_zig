const std = @import("std");
const ComplexStream = @import("complexStream");
const sysOps = @import("sysOps");
const config = @import("config");
const login = @import("login.zig");

const SIZE_FOR_BUFFERS = 4096;


//##############################################################################
// Function:    generic_poster
//
// Description: This is the POST router. Targets under /archival/ are treated
//              as video uploads and handed to archive_payload. /login is
//              handed to login.manage_attempt. Anything else is logged and
//              ignored so an unexpected POST does not get a half-handled
//              write.
//##############################################################################
pub fn generic_poster(
    allocator : std.mem.Allocator,
    io : std.Io,
    stream : *ComplexStream
) void {
    std.debug.print("I'm in a poster right now...\n", .{});
    std.log.debug("My header_target at start of poster is: {s}\n", .{stream.header_target});
    if (determine_if_video_upload(stream)) {
        std.log.debug("Post request IS video archival\n", .{});
        archive_payload(allocator, io, stream);
    }
    else if (std.mem.eql(u8, stream.header_target, "/login")) {
        login.manage_attempt(io, allocator, stream);
    }
    else {
        std.log.debug("Post request is something other than a video archival\n", .{});
        std.log.debug("\tHeader target is {s}\n", .{ stream.header_target });
    }
}


//##############################################################################
// Function:    determine_if_video_upload
//
// Description: This function returns true when the request target starts
//              with /archival/. That prefix is how cameras (or the
//              uploader) mark a clip that should be written under
//              Archives/ rather than treated as a login or an unknown
//              POST.
//##############################################################################
fn determine_if_video_upload(stream : *const ComplexStream) bool {
    return std.mem.startsWith(u8, stream.header_target, "/archival/");
}


//##############################################################################
// Function:    archive_payload
//
// Description: This is the full archival path for a camera upload. It
//              derives an Archives/... path from the target, rejects with
//              409 if that file already exists (so a client cannot
//              clobber a clip it already sent), creates parent dirs,
//              streams the POST body into the new file, then ACKs.
//
//              Several failure points are still @panic TODOs - this is
//              the path that most needs a real error response once those
//              are decided.
//##############################################################################
fn archive_payload(
    allocator : std.mem.Allocator,
    io : std.Io,
    stream : *ComplexStream
) void {

    //Get the path of what we're trying to archive...
    const archive_path = get_desired_path_for_archival(allocator, stream) catch {
        @panic("Handle when the path could not be found in the POST message\n");
    };
    defer allocator.free(archive_path);
    std.log.debug("value of var \"archive_path\" is: {s}\n", .{ archive_path });

    //Handle the process of addressing a bad request where the client tries to
    //rearchive a file that it's already archived on the server
    const file_exists = check_if_file_already_exists(io, archive_path);

    if (file_exists) {
        stream.request.respond(
            "",
            .{ 
                .keep_alive = false,
                .status = .conflict,
            }
        ) catch |err| {
            std.log.err("Error: {any}\n", .{ err });
            @panic("Error responding to client");
        };
        return;
    }

    //const folder_status = ensure_directory_exists(io, archive_path) catch {
    _ = ensure_directory_exists(io, archive_path) catch {
        @panic("TODO: handle inability to create folder to house archive files\n");
    };

    // Trying to create the file descriptor that we'll write/archive to
    const new_file = std.Io.Dir.createFile(.cwd(), io, archive_path, .{}) catch |err| {
        std.log.err("There was an error in creating the new file that the payload would write to. Error code: {any}\n", .{ err });
        @panic("TODO: Send an error code to the client that indicates that client may need to attempt again\n");
    };

    var buffer_for_stream_reader : [SIZE_FOR_BUFFERS]u8 = std.mem.zeroes([SIZE_FOR_BUFFERS]u8);
    var buffer_for_file_writer : [SIZE_FOR_BUFFERS]u8 = std.mem.zeroes([SIZE_FOR_BUFFERS]u8);

    var new_file_writer = std.Io.File.writer(new_file, io, &buffer_for_file_writer);

    var alt_stream_reader = stream.request.readerExpectNone(&buffer_for_stream_reader);

    while(alt_stream_reader.fillMore()) {
        defer alt_stream_reader.tossBuffered();
        _ = new_file_writer.interface.write(alt_stream_reader.buffered()) catch {
            @panic("Unhandled error for writing to new file\n");
        };
    }
    else |err| {
        if (error.EndOfStream != err) {
            @panic("Unhandled file writing error\n");
        }
    }

    stream.request.respond("", .{ .keep_alive = false }) catch |err| {
        std.log.err("Error: {any}\n", .{ err });
        @panic("Error responding to client");
    };
}


//##############################################################################
// Function:    get_desired_path_for_archival
//
// Description: This function strips /archival/ from the request target and
//              prefixes Archives/ so the on-disk path matches the URL the
//              camera posted to. The resulting path is allocated for the
//              caller to free.
//
//              If the target does not contain that prefix (it should, if
//              determine_if_video_upload already ran), this returns an
//              error instead of inventing a path.
//##############################################################################
fn get_desired_path_for_archival(
    allocator : std.mem.Allocator,
    stream: *const ComplexStream
) ![]const u8 {
    const nullable_cut = std.mem.cut(u8, stream.header_target, "/archival/");

    const suspected_path = if (nullable_cut) |cut| blk: {
        break :blk cut.@"1";
    }
    else {
        return error.PathInvalid_ArchivalSplitFail;
    };

    return std.fmt.allocPrint(allocator, "Archives/{s}", .{ suspected_path });
}


//##############################################################################
// Function:    check_if_file_already_exists
//
// Description: This is a statFile helper used before archival writes.
//              FileNotFound means we are clear to create the clip. Any
//              other stat result - including unexpected errors - is
//              treated as "exists" so we do not clobber something we
//              could not inspect.
//##############################################################################
fn check_if_file_already_exists(io : std.Io, path : []const u8) bool {
    const failable_stat = std.Io.Dir.statFile(.cwd(), io, path, .{ .follow_symlinks = false});

    if (failable_stat) |_| {
        return true;
    }
    else |err| {
        if (err == error.FileNotFound) {
            return false;
        }
        return true;
    }
}


//##############################################################################
// Function:    ensure_directory_exists
//
// Description: This function takes the full archive file path, drops the
//              last segment (the filename), and createDirPathStatus so
//              nested camera/date folders exist before the file is
//              created. A path with no slash is treated as an error
//              because that would mean we have nowhere to put the clip.
//##############################################################################
fn ensure_directory_exists(io : std.Io, archive_path : []const u8) !std.Io.Dir.CreatePathStatus {
    const nullable_cut = std.mem.cutLast(u8, archive_path, "/");

    const directory = if (nullable_cut) |cut| blk: {
        break :blk cut.@"0";
    }
    else {
        return error.NoDirRequested;
    };

    return try std.Io.Dir.createDirPathStatus(.cwd(), io, directory, .default_dir);
}


//##############################################################################
// Function:    temporary_print_contents
//
// Description: This is a debug helper that dumps the remaining POST body
//              to stdout. It is not on the live routing path - leftover
//              from when the body format was still being figured out.
//##############################################################################
fn temporary_print_contents(
    io : std.Io,
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) void {
    _ = &allocator;
    _ = &io;
    //var reader_backing_buffer : [512]u8 = undefined;
    //var reader = stream.stream.reader(io, &reader_backing_buffer);

    var bytes_remaining : u64 = blk: {
        if (stream.content_length) |len| { break :blk len; }
        else { return; }
    };

    std.debug.print("Buffered Content:\n", .{});
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
        stream.raw_stream_reader.interface.fill(bytes_to_read) catch return;
        defer stream.raw_stream_reader.interface.tossBuffered();
        std.debug.print("{s}", .{ stream.raw_stream_reader.interface.buffered() });

    }
}

//******************************************************************************
//* Function:    parse_and_validate_creds
//*
//* Description: This is an older login-body parser that copies the POST
//               body, splits the first line into username/password, and
//               prints whether config.check_user_credential accepts the
//               pair.
//
//               Login handling has since moved to login.zig
//               (manage_attempt / extract_creds). This looks leftover and
//               is not called from generic_poster.
//******************************************************************************
fn parse_and_validate_creds(
    allocator : std.mem.Allocator,
    stream : *ComplexStream,
) !void {
    var response : std.ArrayList([]const u8) = .empty;

    var bytes_remaining : u64 = blk: {
        if (stream.content_length) |len| { break :blk len; }
        else { return; }
    };

    std.debug.print("Buffered Content:\n", .{});
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
        stream.raw_stream_reader.interface.fill(bytes_to_read) catch return;
        //defer stream.raw_stream_reader.interface.tossBuffered();

        const foo = stream.raw_stream_reader.interface.buffered();
        var lines = std.mem.splitScalar(u8, foo, '\n');
        while (lines.next()) |line| {
            const duped_line = try allocator.dupe(u8, line);
            try response.append(allocator, duped_line);
            stream.raw_stream_reader.interface.toss(line.len);
        }
    }

    defer {
        for (response.items) |line| {
            allocator.free(line);
        }
        response.deinit(allocator);
    }

    const username_full, const password_full = std.mem.cut(
        u8,
        response.items[0],
        "&",
    ) orelse return error.NoAmpersand;
    _, const username = std.mem.cut(
        u8,
        username_full,
        "=",
    ) orelse return error.NoEqualsUsername;
    _, const password = std.mem.cut(
        u8,
        password_full,
        "=",
    ) orelse return error.NoEqualsPassword;

    std.debug.print("Username: {s}\nPassword: {s}\n", .{username, password});
    if (config.check_user_credential(username, password)) {
        std.debug.print("User is valid.\n", .{});
    }
    else {
        std.debug.print("User is prohibited.\n", .{});
    }
}
