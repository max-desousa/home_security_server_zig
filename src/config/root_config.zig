//! This module is specific to handling the config file (config.zap by default)
//!
//! This project has some settings that are configurable. As opposed to pasing
//! these settings as arguemnts, the config.zap file will contain these values.
//! This module contains the logic that will assess if the config.zap doesn't
//! exist, a default will be provided. Then, the original or default file will
//! be parsed to set values that can be read to govern project behavior. 
//!
//! Why not use arguments? 
//! I'm building this project with a target audience in mind that I want to
//! help run this with fewer complications. They will need some degree of tech
//! savy'ness, but if the config file is used, then users can avoid convoluted
//! startups that are prone to issues. (modifying a settings file is easier
//! than countless arguments)


//##############################################################################
//################################# Imports ####################################
//##############################################################################


const std = @import("std");
const auth = @import("auth");


//##############################################################################
//############################# Global Variables ###############################
//##############################################################################


// Const keeping track of config file name to prevent mismatching references 
// leading to runtime errors
const CONFIG_FILE_NAME = "config.zap";


//------------------------------------------------------------------------------


// Fields in config file to be parsed stored as const strings to prevent typos
// in the varios references in parsing/writing leading to runtime errors


const FIELD_DESIRED_HOST = "[ requested host address ]";
const FIELD_DESIRED_PORT = "[ requested port ]";
const FIELD_LISTEN_INTERFACE = "[ listen interface ]";
const FIELD_USER_CREDENTIAL = "[ Authorized login ]";


//------------------------------------------------------------------------------


// Backing values of the fields in the config file
var BUFFER_FOR_VALUE_DESIRED_HOST : [256]u8 = undefined;
var VALUE_DESIRED_HOST: []const u8 = BUFFER_FOR_VALUE_DESIRED_HOST[0..0];

var VALUE_DESIRED_PORT : u16 = undefined;

// Optional SO_BINDTODEVICE name. Null / empty means accept on every interface
// the process can see (the dual-homed default: house LAN + bat0).
const LISTEN_INTERFACE_NAME_MAX = 16;
var BUFFER_FOR_LISTEN_INTERFACE : [LISTEN_INTERFACE_NAME_MAX]u8 = undefined;
var VALUE_LISTEN_INTERFACE: ?[]const u8 = null;


//##############################################################################
//######################## Simple Accessing Functions ##########################
//##############################################################################

// Getters for the config values to make them immutable to consumers of the 
// module


//******************************************************************************
//* Function:    get_desired_host
//*
//* Description: This is a getter for the host address parsed out of config.zap.
//               The backing value is module-private so other modules cannot
//               mutate it after startup. This is only valid after
//               establish_config has run.
//******************************************************************************
pub fn get_desired_host() []const u8 {
    return VALUE_DESIRED_HOST;
}


//******************************************************************************
//* Function:    get_desired_port
//*
//* Description: This is a getter for the listen port parsed out of config.zap.
//               Same reasoning as get_desired_host - consumers should not be
//               able to change the configured port at runtime. This is only
//               valid after establish_config has run.
//******************************************************************************
pub fn get_desired_port() u16 {
    return VALUE_DESIRED_PORT;
}


//******************************************************************************
//* Function:    get_listen_interface
//*
//* Description: Optional NIC name from config.zap. Null means the listen
//*              socket is not restricted with SO_BINDTODEVICE. Only valid
//*              after establish_config has run.
//******************************************************************************
pub fn get_listen_interface() ?[]const u8 {
    return VALUE_LISTEN_INTERFACE;
}


//##############################################################################
//########################### Function Defintions ##############################
//##############################################################################


//******************************************************************************
//* Function:    establish_config
//*
//* Description: This is the startup hook for configuration. It tries to open
//               config.zap, and if that file is present it is parsed so the
//               rest of the program can read host, port, and credentials.
//
//               If the file does not exist, a default is written instead so a
//               first-time run still has something to bind with. Any other
//               open error is treated as fatal and propagated to the caller.
//******************************************************************************
pub fn establish_config(io : std.Io, allocator : std.mem.Allocator) !void {
    if (std.Io.Dir.openFile(std.Io.Dir.cwd(), io, CONFIG_FILE_NAME, .{})) |file| {
        defer file.close(io);
        try parse_file(io, allocator, file);
    }
    else |err| {
        if (std.Io.File.OpenError.FileNotFound == err) {
            try make_default_config(io);
        }
        else return err;
    }
}


//******************************************************************************
//* Function:    parse_file
//*
//* Description: This function walks config.zap line by line and fills the
//               module's backing values. Lines are expected as
//               "field = value". Blank lines and '#' comments are skipped
//               so the file can document the dual-homed / batman-adv bind.
//               Host is copied into a static buffer, port is parsed as a
//               u16, an optional listen-interface name is stored (empty
//               means all interfaces), and each authorized-login line is
//               split into username/password/timeout then appended onto
//               auth.VALUE_USER_CREDENTIALS.
//
//               Credential strings have to be allocated here because we do not
//               know how many users the file will declare, and those
//               allocations live until freeAllocations at shutdown.
//******************************************************************************
fn parse_file(
    io : std.Io,
    allocator : std.mem.Allocator,
    file : std.Io.File
) !void {
    var reader_buffer : [512]u8 = undefined;
    var file_reader = std.Io.File.reader(file, io, &reader_buffer);
    while (file_reader.interface.takeDelimiter('\n')) |nullable_line| {
        const raw = nullable_line orelse break;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse return error.BadInputFile;
        const before = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (std.mem.eql(u8, before, FIELD_DESIRED_HOST)) {
            @memmove(BUFFER_FOR_VALUE_DESIRED_HOST[0..value.len], value);
            VALUE_DESIRED_HOST = BUFFER_FOR_VALUE_DESIRED_HOST[0..value.len];
        }
        else if (std.mem.eql(u8, before, FIELD_DESIRED_PORT)) {
            VALUE_DESIRED_PORT = try std.fmt.parseInt(u16, value, 10);
        }
        else if (std.mem.eql(u8, before, FIELD_LISTEN_INTERFACE)) {
            if (value.len == 0) {
                VALUE_LISTEN_INTERFACE = null;
            }
            else {
                if (value.len >= BUFFER_FOR_LISTEN_INTERFACE.len) {
                    return error.ListenInterfaceNameTooLong;
                }
                @memmove(BUFFER_FOR_LISTEN_INTERFACE[0..value.len], value);
                VALUE_LISTEN_INTERFACE = BUFFER_FOR_LISTEN_INTERFACE[0..value.len];
            }
        }
        else if (std.mem.eql(u8, before, FIELD_USER_CREDENTIAL)) {
            var iterator = std.mem.splitScalar(u8, value, '/');
            const username = iterator.next() orelse @panic("Invalid config for credential - couldn't find username");
            const password = iterator.next() orelse @panic("Invalid config for credential - couldn't find password");
            const timeout_string = iterator.next() orelse @panic("Invalid config for credential - couldn't find timeout");
            const timeout = std.fmt.parseInt(i64, timeout_string, 10) catch |err| {
                std.log.err("Couldn't convert user credential timeout from text to a number during config. Error reported is: \"{any}\"", .{ err });
                return err;
            };

            const allocated_username = try allocator.dupe(u8, username);
            const allocated_password = try allocator.dupe(u8, password);
            try auth.VALUE_USER_CREDENTIALS.append(
                allocator, 
                .{
                    .username = allocated_username,
                    .password = allocated_password,
                    .configured_timeout = timeout,
                }
            );
        }
        else {
            std.log.err("Unknown config field: {s}", .{ before });
            return error.UnknownConfigField;
        }
    } else |err| {
        std.debug.print("Error reading file: {any}\n", .{err});
    }
}


//******************************************************************************
//* Function:    make_default_config
//*
//* Description: This function is used when config.zap is missing. It creates
//               the file with a localhost host and port 3490 so the server
//               can still start without a hand-written config.
//
//               It also seeds the in-memory host/port at the same time. That
//               way a first-time run does not need a second parse pass just
//               to pick up the defaults it just wrote.
//******************************************************************************
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

    try writer.print("# First-run default is loopback so a missing config.zap is not reachable\n", .{});
    try writer.print("# from the house LAN or the camera mesh. Change the host to 0.0.0.0 and\n", .{});
    try writer.print("# see NETWORKING.md when this box is dual-homed (eth0 + bat0).\n", .{});

    const localhost = "127.0.0.1";
    @memmove(BUFFER_FOR_VALUE_DESIRED_HOST[0..localhost.len], localhost);
    VALUE_DESIRED_HOST = BUFFER_FOR_VALUE_DESIRED_HOST[0..localhost.len];
    try writer.print("{s} = {s}\n", .{FIELD_DESIRED_HOST, VALUE_DESIRED_HOST});

    VALUE_DESIRED_PORT = 3490;
    try writer.print("{s} = {d}\n", .{FIELD_DESIRED_PORT, VALUE_DESIRED_PORT});

    VALUE_LISTEN_INTERFACE = null;
    try writer.print("{s} = \n", .{FIELD_LISTEN_INTERFACE});
    
    try file_writer.end();
}


