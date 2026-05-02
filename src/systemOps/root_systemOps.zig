const std = @import("std");
const html_preamble = @embedFile("serve_dir_preamble.txt");
const ComplexStream = @import("complexStream");

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
    std.Io.Dir.access(.cwd(), io, stream.fs_adjusted_target, .{ .read = true }) catch |err| {
        if (error.FileNotFound == err) {
            std.log.debug("request_is_directory returned false for path {s}\n", .{ stream.header_target });
            return false;
        }
    };
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
    try html_file_writer.interface.print("<script>\n", .{});
    try html_file_writer.interface.print("\tconst currentPath = \"{s}\";\n", .{ path[1..path.len] });
    try html_file_writer.interface.print("\tstart(currentPath);\n", .{});
    try html_file_writer.interface.print("\tonHasParentDirectory(currentPath);\n", .{});
    try html_file_writer.interface.print("</script>\n", .{});

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
