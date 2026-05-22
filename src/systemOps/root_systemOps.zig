const std = @import("std");
const ComplexStream = @import("complexStream");
const html_preamble = @embedFile("serve_dir_preamble.txt");

pub fn open_static_html(io : std.Io, path : []const u8) !?std.Io.File {
    var path_buffer : [512]u8 = std.mem.zeroes([512]u8);
    const sub_path = try std.fmt.bufPrint(&path_buffer, "static/{s}.html", .{path});
    const file = std.Io.Dir.openFile(
        std.Io.Dir.cwd(),
        io,
        sub_path,
        .{}
    ) catch |err| {
        // At the moment, I like the idea of returning null - instead of an
        // error - when the file is simply not present. (Trying to open a file
        // that doesn't exist? Successfully return a failed option... seems
        // like it makes good use of the option)
        if (std.Io.File.OpenError.FileNotFound == err) {
            return null;
        }
        else return err;
    };
    return file;
}


//******************************************************************************
//* Function:    
//* 
//* Description: 
//******************************************************************************
pub fn request_is_directory(io : std.Io, stream : *ComplexStream) bool {
    const dir = std.Io.Dir.openDir(.cwd(), io, stream.fs_adjusted_target, .{}) catch |err| {
        if ((error.FileNotFound == err) or (error.NotDir == err)) {
            std.log.debug("request_is_directory returned false for path {s}\n", .{ stream.header_target });
            return false;
        }
        else {
            std.log.info("We're making this request as NOT a dir. Need to consider error: {any} for different evaluation if this is wrong", .{ err });
            return false;
        }
    };
    defer dir.close(io);
    std.log.debug("request_is_directory returned true for path {s}\n", .{ stream.header_target });
    return true;
}


//******************************************************************************
//* Function:    generate_folder_html
//* 
//* Description: 
//******************************************************************************
pub fn generate_html_for_folder(
    io : std.Io,
    html_file : *std.Io.File,
    path : []const u8
) !void {
    var buffer_html_file_writer : [2048]u8 = undefined;
    var html_file_writer = html_file.writer(io, &buffer_html_file_writer);
    defer html_file_writer.interface.flush() catch {};

    try html_file_writer.interface.writeAll(html_preamble);
    try html_file_writer.interface.print("<script>start(\"{s}\");</script>\n", .{ path[1..path.len] });
    try html_file_writer.interface.print("<script>onHasParentDirectory();</script>\n", .{});
    defer html_file_writer.interface.print("<script>finalizeDirectory();</script>\n", .{}) catch {};

    var dir_to_scan = try std.Io.Dir.openDir(
        .cwd(),
        io,
        path,
        .{ 
            .iterate = true,
            .follow_symlinks = false,
        }
    );
    defer dir_to_scan.close(io);

    var dir_iterator = dir_to_scan.iterate();

    while (dir_iterator.next(io)) |nullable_entry| {
        const entry = nullable_entry orelse break;
        var backing_buffer_date_modified_string : [254]u8 = undefined;
        switch (entry.kind) {
            .file => {
                const file_stat = try std.Io.Dir.statFile(dir_to_scan, io, entry.name, .{});
                var backing_buffer_file_size_string : [64]u8 = undefined;
                const file_size_string = try file_bytes_to_abbreviated_string(
                    file_stat.size, 
                    &backing_buffer_file_size_string
                );
                const time_stamp_string = try timestamp_to_string(file_stat.mtime, &backing_buffer_date_modified_string);
                try html_file_writer.interface.print("<script>addRow(\"{s}\",\"{s}\",0,{d},\"{s}\",{d},\"{s}\");</script>\n", .{ entry.name, entry.name, file_stat.size, file_size_string, file_stat.mtime.nanoseconds, time_stamp_string });
            },
            .directory => {
                try html_file_writer.interface.print("<script>addRow(\"{s}\",\"{s}\",1,4096,\"4.0 kB\",0,\"99/99/99, 00:00:00 PM\");</script>\n", .{ entry.name, entry.name });
            },
            else => continue,
        }
    }
    else |err| {
        std.log.err("Error iterating over dir during html file generation: {any}\n", .{ err });
        return err;
    }
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn file_bytes_to_abbreviated_string(bytes : u64, buffer : []u8) ![]const u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB" };
    var value : f64 = @floatFromInt(bytes);
    var unit_index : usize = 0;

    while ((value >= 1024.0) and 
           (unit_index < (units.len - 1))) {
        value /= 1024.0;
        unit_index += 1;
    }

    return try std.fmt.bufPrint(buffer, "{d:.2} {s}", .{ value, units[unit_index] });
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn timestamp_to_string(timestamp : std.Io.Timestamp, buffer : []u8) ![]const u8 {
    const epoch_seconds : std.time.epoch.EpochSeconds = .{ .secs = @intCast(@divTrunc(timestamp.nanoseconds, std.time.ns_per_s)) };

    const epoch_day = epoch_seconds.getEpochDay();
    const year_and_day = epoch_day.calculateYearDay();
    const year = year_and_day.year;

    const month_and_day = year_and_day.calculateMonthDay();
    const day = month_and_day.day_index;
    const month = month_and_day.month.numeric();

    const day_seconds = epoch_seconds.getDaySeconds();

    //99/99/99, 00:00:00 PM
    return try std.fmt.bufPrint(
        buffer,
        "{d:0>2}/{d:0>2}/{d:0>4}, {d:0>2}:{d:0>2}:{d:0>2}",
        .{
            month,
            day,
            year,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    );
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn get_single_file_filelist_for_playlist(
    allocator : std.mem.Allocator,
    parameter_string : []const u8,
) !std.ArrayList([]const u8) {
    _, const file_name = std.mem.cutLast(u8, parameter_string, "/") orelse return error.BadString;
    var file_list : std.ArrayList([]const u8) = .empty;
    const allocated_slice = try allocator.dupe(u8, file_name);
    try file_list.append(allocator, allocated_slice);
    return file_list;
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn get_multi_file_filelist_for_playlist(
    io : std.Io,
    allocator : std.mem.Allocator,
    parameter_string : []const u8,
) !std.ArrayList([]const u8) {
    // Chunking out the relevant strings from the playlist request. 
    const current_dir_padded, const playlist_intermediary = std.mem.cutLast(u8, parameter_string, "/") orelse return error.ParsingNoSlashPresent;
    const current_dir = current_dir_padded[1..current_dir_padded.len];
    const start_time_itermediary0, const playlist_end = std.mem.cutLast(u8, playlist_intermediary, "=") orelse return error.ParsingNoEqualPresent;
    _, const start_time_itermediary1 = std.mem.cut(u8, start_time_itermediary0, "=") orelse return error.ParsingNoSecondEqualPresent;
    const playlist_start, _ = std.mem.cut(u8, start_time_itermediary1, "&") orelse return error.ParsingNoAmpersandPresent;

    return try get_sorted_array_list_of_files(
        io,
        allocator,
        current_dir,
        playlist_start,
        playlist_end
    );
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn get_filelist_for_playlist(
    io : std.Io,
    allocator : std.mem.Allocator,
    parameter_string : []const u8,
) !std.ArrayList([]const u8) {
    if (std.mem.endsWith(u8, parameter_string, "?m3u8")) {
        const file_path, _ = std.mem.cutLast(u8, parameter_string, "?m3u8") orelse return error.MissingM3U8;
        return try get_single_file_filelist_for_playlist(
            allocator,
            file_path,
        );
    }
    else {
        return try get_multi_file_filelist_for_playlist(
            io,
            allocator,
            parameter_string,
        );
    }
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//*
//* Info: The current form of the string that would be passed to the function is:
//  "/Archives/NewCamera_2527704881/?m3u8&start=20251207_1022&end=20251213_1022"
//
//  It points to:
//    - Archives (all playlist requests *should* be from archives)
//    - The camera name we're querying
//    - The start and end point of the duration we're looking to serve. 
//******************************************************************************
pub fn generate_and_get_playlist_file(
    io : std.Io, 
    allocator : std.mem.Allocator,
    parameter_string : []const u8
) !std.Io.File {
    const current_dir_padded, _ = std.mem.cutLast(u8, parameter_string, "/") orelse return error.ParsingNoSlashPresent;
    const current_dir = current_dir_padded[1..current_dir_padded.len];

    var file_list = try get_filelist_for_playlist(
        io,
        allocator,
        parameter_string,
    );
    defer {
        for (file_list.items) |item| {
            allocator.free(item);
        }
        file_list.deinit(allocator);
    }
    std.log.debug("Debug point 0: De we get to the point of iterating over the list?\n", .{});
    for (file_list.items) |item| {
        std.debug.print("\t-- Item being added to playlist file: {s}\n", .{ item });
    }
    std.log.debug("Debug point 1: Do we iterate over the list?\n", .{});

    //Create and write playlist file
    var backing_buffer_for_playlist_file_path : [128]u8 = undefined;
    const playlist_file_path = try std.fmt.bufPrint(&backing_buffer_for_playlist_file_path, "{s}/.playlist.m3u8", .{ current_dir });
    std.log.debug("The path for the file that I'm trying to make (relevant to cwd) is: {s}\n", .{ current_dir });
    var playlist_file = try std.Io.Dir.createFile(.cwd(), io, playlist_file_path, .{ .read = true });

    var backing_buffer_for_playlist_writer : [256]u8 = undefined;
    var playlist_file_writer_full = playlist_file.writer(io, &backing_buffer_for_playlist_writer);
    var playlist_file_writer = &playlist_file_writer_full.interface;

    //Here we are actually writing the playlist file - eveything before this
    //was setup. 
    try playlist_file_writer.print("#EXTM3U\n", .{});
    try playlist_file_writer.print("#EXT-X-VERSION:3\n", .{});
    try playlist_file_writer.print("#EXT-X-TARGETDURATION:10\n", .{});
    try playlist_file_writer.print("#EXT-X-MEDIA-SEQUENCE:0\n", .{});
    try playlist_file_writer.print("#EXT-X-PLAYLIST-TYPE:VOD\n\n", .{});
    for (file_list.items) |item| {
        std.log.debug("Working on adding item to playlist: {s}\n", .{ item });
        //For precision - we're going to calculate the duration of the clip
        //(generally unnecessary, but to hit clean bounds always within the
        //same minute - the client may have shorter clips as it approaches the
        //end of the starting minute.) It's unclear how necessary this is to be
        //accurate... so we'll do the calculation and learn if we can optimize
        //in the future. 
        const base_name, _ = std.mem.cutLast(u8, item, ".") orelse return error.DurationCalc0;
        const intermediary, const end_seconds_string = std.mem.cutLast(u8, base_name, "_") orelse return error.DurationCalc1;
        _, const start_seconds_string = std.mem.cutLast(u8, intermediary, "_") orelse return error.DurationCalc2;

        const start_seconds = try std.fmt.parseInt(u8, start_seconds_string, 10);
        const end_seconds = try std.fmt.parseInt(u8, end_seconds_string, 10);

        const duration = @max(start_seconds, end_seconds) - @min(start_seconds, end_seconds);

        try playlist_file_writer.print("#EXTINF:{d}.0,\n", .{ duration });
        //try playlist_file_writer.print("{s}\n", .{ item });
        try playlist_file_writer.print("/{s}/{s}\n", .{ current_dir, item });
    }
    try playlist_file_writer.print("#EXT-X-ENDLIST\n", .{});
    try playlist_file_writer.flush();

    std.log.debug("Done writing playlist file\n", .{});

    //Returning the populated file so that it can be served to the client.
    return playlist_file;
}

fn get_sorted_array_list_of_files(
    io : std.Io,
    allocator : std.mem.Allocator,
    dir_path : []const u8,
    playlist_start : []const u8,
    playlist_end : []const u8,
) !std.ArrayList([]const u8) {
    var iterable_dir = try std.Io.Dir.openDir(
        .cwd(), io,
        dir_path,
        .{
            .access_sub_paths = false,
            .iterate = true,
            .follow_symlinks = false,
        }
    );
    defer iterable_dir.close(io);
    var dir_iterator = iterable_dir.iterate();

    //Initialize ArrayList that we'll use to track the files. 
    var file_list : std.ArrayList([]const u8) = .empty;
    errdefer {
        for (file_list.items) |item| {
            allocator.free(item);
        }
        file_list.deinit(allocator);
    }

    //Iterate over dir and add all relevant files to the arraylist - we'll sort
    //in the next step
    while (dir_iterator.next(io)) |nullable_entry| {
        const entry = nullable_entry orelse break;
        if ('.' == entry.name[0]) continue;
        std.log.debug("Evaluating file for playlist curation: {s}\n", .{ entry.name });
        const intermediary_string, _ = std.mem.cutLast(u8, entry.name, "_") orelse return error.NoUnderscore;
        const video_time_trunc_timestamp, _ = std.mem.cutLast(u8, intermediary_string, "_") orelse return error.NoSecondUnderscore;

        const order_start = std.mem.order(u8, playlist_start, video_time_trunc_timestamp);
        const order_end = std.mem.order(u8, video_time_trunc_timestamp, playlist_end);

        if ((order_start != .gt) and (order_end != .gt)) {
            //add to the array list - this is within the time frame. 
            const allocated_slice = try allocator.dupe(u8, entry.name);
            try file_list.append(allocator, allocated_slice);
        }
    }
    else |err| {
        std.log.err("Error iterating over camera directory to generate playlist: {any}\n", .{ err });
        return err;
    }

    std.mem.sort([]const u8, file_list.items, {}, file_sorting_less_than);

    return file_list;
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn file_sorting_less_than(_ : void,  a : []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
