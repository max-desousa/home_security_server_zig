const std = @import("std");

// Const keeping track of config file name to prevent mismatching references 
// leading to runtime errors
const CONFIG_FILE_NAME = "config.zap";

//##############################################################################

// Fields in config file to be parsed stored as const strings to prevent typos
// in the varios references in parsing/writing leading to runtime errors

const FIELD_DESIRED_HOST = "[ requested host address ]";
const FIELD_DESIRED_PORT = "[ requested port ]";

//##############################################################################

// Backing values of the fields in the config file
var BUFFER_FOR_VALUE_DESIRED_HOST : [256]u8 = undefined;
var VALUE_DESIRED_HOST: []const u8 = BUFFER_FOR_VALUE_DESIRED_HOST[0..0];

var VALUE_DESIRED_PORT : u16 = undefined;

//##############################################################################

// Getters for the config values to make them immutable to consumers of the 
// module

pub fn get_desired_host() []const u8 {
    return VALUE_DESIRED_HOST;
}

pub fn get_desired_port() u16 {
    return VALUE_DESIRED_PORT;
}

//##############################################################################

pub fn establish_config(io : std.Io) !void {
    if (std.Io.Dir.openFile(std.Io.Dir.cwd(), io, CONFIG_FILE_NAME, .{})) |file| {
        defer file.close(io);
        try parse_file(io, file);
    }
    else |err| {
        if (std.Io.File.OpenError.FileNotFound == err) {
            try make_default_config(io);
        }
        else return err;
    }
}

fn parse_file(io : std.Io, file : std.Io.File) !void {
    var reader_buffer : [512]u8 = undefined;
    var file_reader = std.Io.File.reader(file, io, &reader_buffer);
    while (file_reader.interface.takeDelimiter('\n')) |nullable_line| {
        const line = nullable_line orelse break;
        const before, const after = std.mem.cut(u8, line, " = ") orelse return error.BadInputFile;
        if (std.mem.eql(u8, before, FIELD_DESIRED_HOST)) {
            @memmove(BUFFER_FOR_VALUE_DESIRED_HOST[0..after.len], after);
            VALUE_DESIRED_HOST = BUFFER_FOR_VALUE_DESIRED_HOST[0..after.len];
        }
        else if (std.mem.eql(u8, before, FIELD_DESIRED_PORT)) {
            VALUE_DESIRED_PORT = try std.fmt.parseInt(u16, after, 10);
        }
        else {
            unreachable;
        }
    } else |err| {
        std.debug.print("Error reading file: {any}\n", .{err});
    }
}

fn make_default_config(io : std.Io) !void {
    const new_file = try std.Io.Dir.createFile(
        std.Io.Dir.cwd(),
        io,
        CONFIG_FILE_NAME,
        .{},
    );
    defer new_file.close(io);
    
    var writer_buffer : [512]u8 = undefined;
    var file_writer = std.Io.File.writer(new_file, io, &writer_buffer);
    // Flushing without error check to make sure it isn't missed forgotten -
    // but adequate flush at end of function should happen with at least error
    // propogation
    defer file_writer.end() catch {};

    var writer = &file_writer.interface;

    const localhost = "127.0.0.1";
    @memmove(BUFFER_FOR_VALUE_DESIRED_HOST[0..localhost.len], localhost);
    VALUE_DESIRED_HOST = BUFFER_FOR_VALUE_DESIRED_HOST[0..localhost.len];
    try writer.print("{s} = {s}\n", .{FIELD_DESIRED_HOST, VALUE_DESIRED_HOST});

    VALUE_DESIRED_PORT = 3490;
    try writer.print("{s} = {d}\n", .{FIELD_DESIRED_PORT, VALUE_DESIRED_PORT});
    
    try file_writer.end();
}
