const std = @import("std");

// Const keeping track of config file name to prevent mismatching references 
// leading to runtime errors
const CONFIG_FILE_NAME = "config.zap";

//##############################################################################

// Fields in config file to be parsed stored as const strings to prevent typos
// in the varios references in parsing/writing leading to runtime errors

const FIELD_DESIRED_HOST = "[ requested host address ]";
const FIELD_DESIRED_PORT = "[ requested port ]";
const FIELD_USER_CREDENTIAL = "[ Authorized login ]";

//##############################################################################

const UserCredential = struct {
    username : []const u8,
    password : []const u8,
    configured_timeout : i64, //The amount of time that user's cookie is
                              //allowed to be valid for
    cookie : ?[]const u8 = null,
    expiry_time : i64 = 0, //The realtime the cookie expires
};

//##############################################################################

// Backing values of the fields in the config file
var BUFFER_FOR_VALUE_DESIRED_HOST : [256]u8 = undefined;
var VALUE_DESIRED_HOST: []const u8 = BUFFER_FOR_VALUE_DESIRED_HOST[0..0];

var VALUE_DESIRED_PORT : u16 = undefined;

var VALUE_USER_CREDENTIALS : std.ArrayList(UserCredential) = .empty;

//##############################################################################

// Getters for the config values to make them immutable to consumers of the 
// module

pub fn get_desired_host() []const u8 {
    return VALUE_DESIRED_HOST;
}

pub fn get_desired_port() u16 {
    return VALUE_DESIRED_PORT;
}

pub fn check_user_credential(username : []const u8, password : []const u8) bool {
    for (VALUE_USER_CREDENTIALS.items) |valid_credential| {
        if (std.mem.eql(u8, valid_credential.username, username)) {
            if (std.mem.eql(u8, valid_credential.password, password)) {
                return true;
            }
            else {
                return false;
            }
        }
    }
    return false;
}


pub fn update_user_cookie(io : std.Io, username : []const u8, cookie : []const u8) !void {
    const timestamp_now = std.Io.Timestamp.now(io, .real);
    const now_seconds = timestamp_now.toSeconds();
    for (VALUE_USER_CREDENTIALS.items) |*cred| {
        if (std.mem.eql(u8, cred.username, username)) {
            cred.cookie = cookie;
            cred.expiry_time = cred.configured_timeout + now_seconds;
            return;
        }
    }
    return error.UserNotFound;
}


pub fn is_valid_cookie(cookie : []const u8) bool {

    for (VALUE_USER_CREDENTIALS.items, 0..) |cred, i| {
        std.log.debug("User[{d}]:", .{i});
        std.log.debug("\tusername: {s}", .{cred.username});
        std.log.debug("\tpassword: {s}", .{cred.password});
        if (cred.cookie) |ckie| {
            std.log.debug("\tcookie: {s}", .{ckie});
        }
        else {
            std.log.debug("\tNo cookie present", .{});
        }
        std.log.debug("\tconfigured timeout: {d}", .{cred.configured_timeout});
        std.log.debug("\texpiry time: {d}", .{cred.expiry_time});
    }

    for (VALUE_USER_CREDENTIALS.items) |cred| {
        const credential_cookie = cred.cookie orelse continue;
        std.log.debug("Comparing {s} and {s}", .{credential_cookie, cookie});
        if (std.mem.eql(u8, credential_cookie, cookie)) {
            return true;
        }
    }
    std.log.err("During check for valid cookie - server is saying no matches for cookie {s}", .{cookie});
    return false;
}


//##############################################################################

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

fn parse_file(
    io : std.Io,
    allocator : std.mem.Allocator,
    file : std.Io.File
) !void {
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
        else if (std.mem.eql(u8, before, FIELD_USER_CREDENTIAL)) {
            var iterator = std.mem.splitScalar(u8, after, '/');
            const username = iterator.next() orelse @panic("Invalid config for credential - couldn't find username");
            const password = iterator.next() orelse @panic("Invalid config for credential - couldn't find password");
            const timeout_string = iterator.next() orelse @panic("Invalid config for credential - couldn't find timeout");
            const timeout = std.fmt.parseInt(i64, timeout_string, 10) catch |err| {
                std.log.err("Couldn't convert user credential timeout from text to a number during config. Error reported is: \"{any}\"", .{ err });
                return err;
            };

            const allocated_username = try allocator.dupe(u8, username);
            const allocated_password = try allocator.dupe(u8, password);
            try VALUE_USER_CREDENTIALS.append(
                allocator, 
                .{
                    .username = allocated_username,
                    .password = allocated_password,
                    .configured_timeout = timeout,
                }
            );
        }
        else {
            unreachable;
        }
    } else |err| {
        std.debug.print("Error reading file: {any}\n", .{err});
    }
}

pub fn freeAllocations(allocator : std.mem.Allocator) void {
    for (VALUE_USER_CREDENTIALS.items) |entry| {
        allocator.free(entry.username);
        allocator.free(entry.password);
        if (entry.cookie) |cookie| {
            allocator.free(cookie);
        }
    }
    VALUE_USER_CREDENTIALS.deinit(allocator);
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


pub fn cookie_expiry_time(
    cookie : []const u8,
) ?i64 {
    for (VALUE_USER_CREDENTIALS.items) |cred| {
        const credential_cookie = cred.cookie orelse continue;
        if (std.mem.eql(u8, credential_cookie, cookie)) {
            return cred.expiry_time;
        }
    }
    return null;
}
