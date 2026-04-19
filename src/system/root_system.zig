const std = @import("std");


//##############################################################################
// Function: 
//
// Description: 
//##############################################################################
pub fn get_size_of_archive(
    io : std.Io,
    allocator : std.mem.Allocator,
) !u64 {
    const iterable_directory = std.Io.Dir.openDir(
        .cwd(), 
        io, 
        "Archives",
        .{
            .iterate = true,
            .follow_symlinks = false,
        }
    ) catch |err| {
        switch (err) {
            error.FileNotFound => return 0,
            else => return err,
        }
    };
    defer iterable_directory.close(io);

    var dir_walker = try iterable_directory.walk(allocator);
    defer dir_walker.deinit();

    var running_calculation : u64 = 0;
    while (dir_walker.next(io)) |nullable_entry| {
        const entry = nullable_entry orelse break;
        if (.file != entry.kind) {
            continue;
        }
        const file = try std.Io.Dir.openFile(iterable_directory, io, entry.path, .{});
        defer file.close(io);

        const file_stat = try file.stat(io);
        running_calculation += file_stat.size;
    }
    else |err| {
        return err;
    }

    return running_calculation;
}


//##############################################################################
// Function: 
//
// Description: 
//##############################################################################
pub fn cleanup_archive(
    io : std.Io,
    allocator : std.mem.Allocator,
    current_size_of_archive : u64,
    threshold : u64,
) !void {
    const iterable_directory = std.Io.Dir.openDir(
        .cwd(), 
        io, 
        "Archives",
        .{
            .iterate = true,
            .follow_symlinks = false,
        }
    ) catch |err| {
        switch (err) {
            error.FileNotFound => return,
            else => return err,
        }
    };
    defer iterable_directory.close(io);

    var dir_walker = try iterable_directory.walk(allocator);
    defer dir_walker.deinit();

    var sortable_file_detail_list : std.ArrayList(*FileDetails) = .empty;
    defer {
        for(sortable_file_detail_list.items) |item| {
            allocator.free(item.file_path);
            allocator.destroy(item);
        }
        sortable_file_detail_list.deinit(allocator);
    }

    while (dir_walker.next(io)) |nullable_entry| {
        const entry = nullable_entry orelse break;
        if (.file != entry.kind) {
            continue;
        }
        const file = try std.Io.Dir.openFile(iterable_directory, io, entry.path, .{});
        defer file.close(io);

        const file_stat = try file.stat(io);
        var new_file_details = try allocator.create(FileDetails);
        new_file_details.file_path = try std.fmt.allocPrint(allocator, "{s}", .{ entry.path });
        const slash_index = std.mem.findLast(u8, new_file_details.file_path, "/") orelse return error.NoSlashForNameParsing;
        const ext_index = std.mem.findLast(u8, new_file_details.file_path, ".") orelse return error.NoPeriodForParsing;
        new_file_details.date_time = new_file_details.file_path[(slash_index + 1)..ext_index];
        new_file_details.size = file_stat.size;
        try sortable_file_detail_list.append(allocator, new_file_details);
    }
    else |err| {
        return err;
    }

    std.mem.sort(*FileDetails, sortable_file_detail_list.items, {}, struct {
        fn lessThan(_: void, a: *FileDetails, b: *FileDetails) bool {
            // Returns true if a should come before b (i.e. a is older)
            return std.mem.order(u8, a.date_time, b.date_time) == .lt;
        }
    }.lessThan);

    var current_size = current_size_of_archive;

    for (sortable_file_detail_list.items) |item| {
        if (current_size < threshold) {
            break;
        }

        try std.Io.Dir.deleteFile(iterable_directory, io, item.file_path);
        current_size -= item.size;
    }
}

const FileDetails = struct {
    file_path : []u8,
    date_time : []u8,
    size : u64,
};
