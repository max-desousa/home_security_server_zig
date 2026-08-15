const std = @import("std");

pub const get = @import("get_handling.zig");
pub const post = @import("post_handling.zig");
pub const general = @import("general_server_functions.zig");
pub const authentication = @import("authentication.zig");

//******************************************************************************
//* Function:    generate_and_serve_directory_html
//*
//* Description: This is a leftover stub on the serverOps root. The working
//               implementation lives in html.zig and is what GET routing
//               actually calls. This function is unused and currently does
//               nothing - kept so the re-export surface is not silently
//               missing a name that used to live here.
//******************************************************************************
pub fn generate_and_serve_directory_html() void {
}

pub const authenticated_user_check = authentication.authenticated_user_check;

pub const stream_processing = general.stream_processing;
