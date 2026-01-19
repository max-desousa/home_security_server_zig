const std = @import("std");

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&

method : RequestType,
req_uri : []const u8,
http_version : []const u8,

stream_reader : *std.Io.net.Stream.Reader,

// Base things to keep (some just to simplify zig argument lists)
allocator : std.mem.Allocator,
io : std.Io,
stream : *std.Io.net.Stream,

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&

const Self = @This();

const RequestType = enum {
    POST,
    GET,
    INVALID,
};

pub fn init(
    allocator : std.mem.Allocator,
    io : std.Io,
    stream : *std.Io.net.Stream
) !Self {

    var buffer_for_stream_reader : [4096]u8 = std.mem.zeroes([4096]u8);
    var stream_reader = stream.reader(io, &buffer_for_stream_reader);

    const method, const uri, const http_version = blk: {
        const nullable_first_line = try stream_reader.interface.takeDelimiter('\n');
        const first_line = nullable_first_line orelse return error.ParsingFirstLine0;
        const nullable_first_cut = std.mem.cut(u8, first_line, " ");
        const first_cut = nullable_first_cut orelse return error.ParsingFirstLineFirstCut;
        const nullable_second_cut = std.mem.cut(u8, first_cut.@"1", " ");
        const second_cut = nullable_second_cut orelse return error.ParsingFirstLineSecondCut;

        const calculated_method : RequestType = meth: {
            if (std.mem.eql(u8, "GET", first_cut.@"0")) {
                break :meth .GET;
            }
            else if (std.mem.eql(u8, "GET", first_cut.@"0")) {
                break :meth .POST;
            }
            else break :meth .INVALID;
        };

        const allocated_uri = try std.fmt.allocPrint(allocator, "{s}", .{second_cut.@"0"});
        errdefer allocator.free(allocated_uri);

        const allocated_version = try std.fmt.allocPrint(allocator, "{s}", .{second_cut.@"1"});
        errdefer allocator.free(allocated_version);

        break :blk .{
            calculated_method,
            allocated_uri,
            allocated_version,
        };
    };

    std.debug.print("Parsed values...\nMethod: {any}\nUri: {s}\nVersion: {s}\n", .{
        method,
        uri,
        http_version,
    });

    return .{
        .method = method,
        .req_uri = uri,
        .http_version = http_version,
        .stream_reader = &stream_reader,
        .allocator = allocator,
        .io = io,
        .stream = stream,
    };
}

pub fn deinit(self : *Self) !void {
    self.allocator.free(self.req_uri);
    self.allocator.free(self.http_version);
}
