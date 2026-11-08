//! HTTP application layer: gate a request, dispatch by method/target, send a response.
//!
//! Thread-facing entry points:
//!   - authenticated_user_check  (may this request proceed?)
//!   - stream_processing         (GET / POST switch)
//!   - send_client_to_login      (unauthenticated redirect)
//!
//! Internal files are not re-exported. Open `get.zig`, `post.zig`, `login.zig`,
//! `playlist.zig`, `directory.zig`, `archive.zig`, or `respond.zig` by name.

pub const authenticated_user_check = @import("request_gate.zig").authenticated_user_check;
pub const stream_processing = @import("dispatch.zig").stream_processing;
pub const send_client_to_login = @import("login.zig").send_client_to_login;
pub const special_camera_upload = @import("specialized_cam_upload.zig").special_camera_upload;
