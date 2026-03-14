const std = @import("std");
const ComplexStream = @import("complexStream");

const SIZE_FOR_BUFFERS = 4096;

pub fn generic_poster(io : std.Io, stream : *ComplexStream) void {
    std.debug.print("I'm in a poster right now...\n", .{});
    if (determine_if_video_upload(stream)) {
        std.log.debug("Post request IS video archival\n", .{});
        archive_payload(io, stream);
    }
    else {
        std.log.debug("Post request is something other than a video archival\n", .{});
    }
}

fn determine_if_video_upload(stream : *const ComplexStream) bool {
    const head = stream.http_request.head;

    std.log.debug("The value of \"head.target\" is: {s}\n", .{ head.target });
    return std.mem.startsWith(u8, head.target, "/archival/");
}

fn archive_payload(io : std.Io, stream : *const ComplexStream) void {

    //Get the path of what we're trying to archive...
    const archive_path = get_desired_path_for_archival(stream) catch {
        @panic("Handle when the path could not be found in the POST message\n");
    };
    std.log.debug("value of var \"archive_path\" is: {s}\n", .{ archive_path });

    //Handle the process of addressing a bad request where the client tries to
    //rearchive a file that it's already archived on the server
    const file_exists = check_if_file_already_exitst(io, archive_path);

    if (file_exists) {
        // TODO: Send rejection
        @panic("TODO: send a rejection to the client that the file already exists on the server and cannot be newly archived\n");
    }

    // Trying to create the file descriptor that we'll write/archive to
    const new_file = std.Io.Dir.createFile(.cwd(), io, archive_path, .{}) catch |err| {
        std.log.err("There was an error in creating the new file that the payload would write to. Error code: {any}\n", .{ err });
        @panic("TODO: Send an error code to the client that indicates that client may need to attempt again\n");
    };
    _ = &new_file;
    unreachable;
}

fn get_desired_path_for_archival(stream: *const ComplexStream) ![]const u8 {
    const nullable_cut = std.mem.cut(u8, stream.http_request.head.target, "/archival/");

    const suspected_path = if (nullable_cut) |cut| blk: {
        break :blk cut.@"1";
    }
    else {
        return error.PathInvalid_ArchivalSplitFail;
    };

    if (1 != std.mem.countScalar(u8, suspected_path, '/')) {
        //Maybe subfolders will be supported in future... 
        return error.PathInvalid_TooManySlashes;
    }

    return suspected_path;
}

fn get_desired_file_name_from_request(stream : *const ComplexStream) ![]const u8 {
    var header_iterator = stream.http_request.iterateHeaders();

    while(header_iterator.next()) |header| {
        if (std.mem.eql(u8, header.name, "FILE_NAME")) {
            return header.value;
        }
    }

    return error.NoFileNameFound;
}

fn get_desired_dir_from_request(stream : *const ComplexStream) ![]const u8 {
    const nullable_cut = std.mem.cutLast(
        u8, 
        stream.http_request.head.target, 
        "/",
    );

    if (nullable_cut) |cut| {
        return cut.@"1";
    }

    return error.NoDirFound;
}

fn check_if_file_already_exitst(io : std.Io, path : []const u8) bool {
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
