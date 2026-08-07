const std = @import("std");

pub const get = @import("get_handling.zig");
pub const post = @import("post_handling.zig");
pub const general = @import("general_server_functions.zig");
pub const authentication = @import("authentication.zig");

pub fn generate_and_serve_directory_html() void {
}

pub const authenticated_user_check = authentication.authenticated_user_check;

pub const stream_processing = general.stream_processing;
