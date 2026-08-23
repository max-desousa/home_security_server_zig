//! This file is specific to the entry point logic that will be used for
//! creating a static page - on request - for a settings page(s).

//==============================================================================
//================================= Imports ====================================
//==============================================================================


const std = @import("std");


//==============================================================================
//================================ Functions ===================================
//==============================================================================


pub fn generate_settings_page(
    io : std.Io,
//) !std.Io.File {
) !void {
    const settings_html = try std.Io.Dir.createFile(
        .cwd(),
        io,
        "./static/settings.html",
        .{} ,
    );
    defer settings_html.close(io);

    var writing_buffer : [512]u8 = undefined;
    var full_writer = settings_html.writer(io, &writing_buffer);
    defer full_writer.end();
    var writer = &full_writer.interface;
    
    writer.print("<!DOCTYPE html>\n<html>\n<body>\n\n", .{});
    writer.print("<h1>Settings Page</h1>\n", .{});
    writer.print("<h2>Server Settings</h2>\n", .{});
    writer.print("<h2>Camera Specific Settings</h2>\n", .{});
    writer.print("\n</body>\n</html>", .{});
}
