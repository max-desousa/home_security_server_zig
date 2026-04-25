const std = @import("std");
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
pub fn request_is_directory(path : []const u8) bool {
    
}

//******************************************************************************
//* Function:    generate_folder_html
//* 
//* Description: 
//******************************************************************************
pub fn generate_folder_html(io : std.Io, path : []const u8) !std.Io.File {
    var html_file = try std.Io.Dir.createFile(.cwd(), io, ".index.html", .{ .lock = .exclusive });
    errdefer html_file.close(io);

    var buffer_html_file_writer : [512]u8 = undefined;
    var html_file_writer = html_file.writer(io, &buffer_html_file_writer);
    defer html_file_writer.interface.flush() catch {};

    try html_file_writer.interface.writeAll(html_preamble);
    try html_file_writer.interface.writeAll(path);
    try html_file_writer.interface.writeAll("\");</script>\n<script>onHasParentDirectory();</script>");

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
        switch (entry.kind) {
            .file => try html_file_writer.interface.writeAll("<script>addRow(\"NewCamera_2527704881\",\"NewCamera_2527704881/index.html\",1,4096,\"4.0 kB\",1776524553,\"4/18/26, 11:02:33 AM\");</script>"),
            .directory => try html_file_writer.interface.writeAll("<script>addRow(\"index.html\",\"index.html\",0,1409,\"1.4 kB\",1777122411,\"4/25/26, 9:06:51 AM\");</script>"),
            else => continue,
        }
    }
    else |err| {
        std.debug.print("Error iterating over dir during html file generation: {any}\n", .{ err });
        return err;
    }
}
