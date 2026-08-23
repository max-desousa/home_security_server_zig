//! This file is specific to the process of conducting operations in the event
//! that the request is for system settings. The system settings is a rather
//! dynamic process. (ex: do we allow certain settings pending the user
//! permissions?)
//!
//! This file is another handoff in handling the request to dynamically
//! calculate the tailored settings page, and serve as an entry point to
//! delineate the settings main page from a camera centric settings page. 


//==============================================================================
//================================= Imports ====================================
//==============================================================================


const std = @import("std");
const ComplexStream = @import("complexStream");


//==============================================================================
//================================ Functions ===================================
//==============================================================================


//******************************************************************************
//* Function:    dispatch_settings_request
//*
//* Description: This function is the top level caller for the request for a
//               page related to settings in some sort. This - to take advantage
//               of the zig featureset - just wraps a version of the function 
//               that is capable of failing.
//
//               The parent calling this function is related to a top level io
//               function and really can't bubble the failure up - the thread
//               just terminates waiting for another connection attempt.
//               (another reason we're wrapping it)
//******************************************************************************
pub fn dispatch_settings_request(
    io : std.Io,
    stream : *ComplexStream,
) void {
    failable_dispatch_settings_request(io, stream) catch {};
}


//******************************************************************************
//* Function:    failable_dispatch_settings_request
//*
//* Description: This handles the routing and a settings request.
//******************************************************************************
pub fn failable_dispatch_settings_request(
    io : std.Io,
    stream : *ComplexStream,
) !void {
    if (std.mem.eql(u8, stream.header_target, "/settings")) {
        generate_and_serve_settings_file(io, stream);
    }
    else {
        const is_valid_subpage = valid_camera_settings_request(io, stream);

        if (is_valid_subpage) {
            generate_and_serve_camera_specific_settings(io, stream);
        }
        else {
            return error.InvalidCameraRequest;
        }
    }
}
