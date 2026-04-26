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
    stream.target_file_system_path = std.fmt.bufPrint(
        &stream.backing_buffer_for_target_filesys_path,
        "Archives{s}",
        .{ stream.header_target }
    ) catch return false;
    
    std.Io.Dir.access(.cwd(), io, stream.target_file_system_path.?, .{ .read = true }) catch |err| {
        if (error.FileNotFound == err) {
            std.log.debug("request_is_directory returned false for path {s}\n", .{ stream.header_target });
            stream.target_file_system_path = null;
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
            .file => {
                try html_file_writer.interface.print("<script>addRow(\"{s}\",\"{s}\",1,69,\"4.0 kB\",7777777,\"88/88/88, 33:33:33 AM\");</script>", .{ entry.name, entry.name });
            },
            .directory => {
                try html_file_writer.interface.print("<script>addRow(\"{s}\",\"{s}\",1,4096,\"4.0 kB\",0,\"99/99/99, 00:00:00 PM\");</script>", .{ entry.name, entry.name });
            },
            else => continue,
        }
    }
    else |err| {
        std.debug.print("Error iterating over dir during html file generation: {any}\n", .{ err });
        return err;
    }
}
