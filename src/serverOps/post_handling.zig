const std = @import("std");
const ComplexStream = @import("complexStream");
const sysOps = @import("sysOps");

const SIZE_FOR_BUFFERS = 4096;


//##############################################################################
// Function: 
//
// Description: 
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
    else {
        std.log.debug("Post request is something other than a video archival\n", .{});
        std.log.debug("\tHeader target is {s}\n", .{ stream.header_target });
    }
}


//##############################################################################
// Function: 
//
// Description: 
//##############################################################################
fn determine_if_video_upload(stream : *const ComplexStream) bool {
    return std.mem.startsWith(u8, stream.header_target, "/archival/");
}


//##############################################################################
// Function: 
//
// Description: 
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
// Function: 
//
// Description: 
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
// Function: 
//
// Description: 
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
// Function: 
//
// Description: 
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
