const std = @import("std");

//pub fn get_request(
//    allocator : std.mem.Allocator,
//    io : std.Io,
//    stream : std.Io.net.Stream) 
//    ![]u8 {
//
//    var buffer_for_stream_reader : [1024]u8 = std.mem.zeroes([1024]u8);
//    var stream_reader = stream.reader(io, &buffer_for_stream_reader);
//
//    std.debug.print("Start of data from client...\n", .{});
//    //while (stream_reader.interface.takeDelimiterInclusive('\n')) |nullable_line| {
//    while (stream_reader.interface.takeDelimiterInclusive('\n')) |line| {
//        if (std.mem.eql(u8, line, "\r\n")) break;
//        std.debug.print("{s}", .{line});
//    } else |err| {
//        if (error.EndOfStream != err) {
//            std.debug.print("Error reading stream: {any}\n", .{err});
//        }
//    }
//}

pub fn get_request_msg(
    allocator : std.mem.Allocator,
    io : std.Io,
    stream : std.Io.net.Stream,
) !?[]u8 {
    var buffer_for_stream_reader : [1024]u8 = std.mem.zeroes([1024]u8);
    var stream_reader = stream.reader(io, &buffer_for_stream_reader);
    const first_line = try stream_reader.interface.peekDelimiterExclusive('\n');
    std.debug.print("\tFirst line was: {s}\n", .{first_line});
    const nullable_first_cut = std.mem.cut(u8, first_line, " ");
    const first_cut = nullable_first_cut orelse return error.BadRequestFromClient;
    std.debug.print("\tFirst cut index 0: {s}\n" ,.{first_cut[0]});
    std.debug.print("\tFirst cut index 1: {s}\n" ,.{first_cut[1]});

    if (!std.mem.eql(u8, first_cut[0], "GET")) {
        return null;
    }

    const nullable_second_cut = std.mem.cut(u8, first_cut[1], " ");
    const second_cut = nullable_second_cut orelse return error.UnknownFormatForRequest;

    return try std.fmt.allocPrint(allocator, "{s}", .{second_cut[0]});
}
