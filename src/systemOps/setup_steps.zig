//! This file is a subset of logic living under the systemOps module
//!
//! The contents of this file are limited to steps that the system will need to
//! run in order for the program to work. 
//!
//! An easy example would be the setps that would be necessary in order for the
//! camera mesh to work. 


//##############################################################################
//################################# Imports ####################################
//##############################################################################


const std = @import("std");


//##############################################################################
//################################ Functions ###################################
//##############################################################################


//******************************************************************************
//* Function:    execute
//*
//* Description: This function is used as the one public caller that should run
//               all downstream steps to set the system up in order for the
//               system to work.
//******************************************************************************
pub fn execute(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    try load_batman(io, allocator);
    try disengage_network_manager(io, allocator);
    try put_radio_into_mesh(io, allocator);
}


//******************************************************************************
//* Function:    revert
//*
//* Description: This function may be limited to when working on active 
//               development - this will remain to be seen. 
//
//               The goal of this funciton though is to restore wifi to normal
//               settings after the program terminates so the developer can
//               continue to use internet.
//******************************************************************************
pub fn revert(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    try put_radio_into_client(io, allocator);
    try reengage_network_manager(io, allocator);
}


//******************************************************************************
//* Function:    load_batman
//*
//* Description: This function will be used to load the batman kernel module
//******************************************************************************
fn load_batman(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    const run_result = try std.process.run(
        allocator,
        io, 
        .{
            .argv = &.{
                "modprobe",
                "batman-adv",
            }
        }
    );
    defer {
        allocator.free(run_result.stderr);
        allocator.free(run_result.stdout);
    }

    // The command has failed - let's let the user know the details before
    // returning an err state
    if (false == run_result.term.success()) {
        std.log.err("Error running batman-adv", .{});
        std.log.info("\tstdout for command: \"{s}\"", .{ run_result.stdout });
        std.log.info("\tstderr for command: \"{s}\"", .{ run_result.stderr });
        var backing_buffer_stderr : [256]u8 = undefined;
        var stderr_writer = std.Io.File.writer(
            .stderr(),
            io,
            &backing_buffer_stderr,
        );
        try run_result.term.format(&stderr_writer.interface);
        try stderr_writer.end();
        return error.CouldNotLoadBatmanKernelModule;
    }
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn disengage_network_manager(
    io : std.Io, 
    allocator : std.mem.Allocator,
) !void {
    const run_result = try std.process.run(
        allocator,
        io, 
        .{
            .argv = &.{
                "nmcli",
                "device",
                "set",
                "wlan0",
                "managed",
                "no",
            }
        }
    );
    defer {
        allocator.free(run_result.stderr);
        allocator.free(run_result.stdout);
    }

    // The command has failed - let's let the user know the details before
    // returning an err state
    if (false == run_result.term.success()) {
        std.log.err("Error disengaging wifi from the network manager", .{});
        std.log.info("\tstdout for command: \"{s}\"", .{ run_result.stdout });
        std.log.info("\tstderr for command: \"{s}\"", .{ run_result.stderr });
        var backing_buffer_stderr : [256]u8 = undefined;
        var stderr_writer = std.Io.File.writer(
            .stderr(),
            io,
            &backing_buffer_stderr,
        );
        try run_result.term.format(&stderr_writer.interface);
        try stderr_writer.end();
        return error.CouldNotDisengageNetworkManager;
    }
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn reengage_network_manager(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    const first_command = try std.process.run(
        allocator,
        io, 
        .{
            .argv = &.{
                "nmcli",
                "device",
                "set",
                "wlan0",
                "managed",
                "yes",
            }
        }
    );
    defer {
        allocator.free(first_command.stderr);
        allocator.free(first_command.stdout);
    }

    // The command has failed - let's let the user know the details before
    // returning an err state
    if (false == first_command.term.success()) {
        std.log.err("Error reengaging wifi with the network manager", .{});
        std.log.info("\tstdout for command: \"{s}\"", .{ first_command.stdout });
        std.log.info("\tstderr for command: \"{s}\"", .{ first_command.stderr });
        var backing_buffer_stderr : [256]u8 = undefined;
        var stderr_writer = std.Io.File.writer(
            .stderr(),
            io,
            &backing_buffer_stderr,
        );
        try first_command.term.format(&stderr_writer.interface);
        try stderr_writer.end();
        return error.CouldNotReengageNetworkManager;
    }

    //const second_command = try std.process.run(
    //    allocator,
    //    io, 
    //    .{
    //        .argv = &.{
    //            "nmcli",
    //            "device",
    //            "connect",
    //            "wlan0",
    //        }
    //    }
    //);
    //defer {
    //    allocator.free(second_command.stderr);
    //    allocator.free(second_command.stdout);
    //}

    //// The command has failed - let's let the user know the details before
    //// returning an err state
    //if (false == second_command.term.success()) {
    //    std.log.err("Error reengaging wifi with the network manager", .{});
    //    std.log.info("\tstdout for command: \"{s}\"", .{ second_command.stdout });
    //    std.log.info("\tstderr for command: \"{s}\"", .{ second_command.stderr });
    //    var backing_buffer_stderr : [256]u8 = undefined;
    //    var stderr_writer = std.Io.File.writer(
    //        .stderr(),
    //        io,
    //        &backing_buffer_stderr,
    //    );
    //    try second_command.term.format(&stderr_writer.interface);
    //    try stderr_writer.end();
    //    return error.CouldNotDisengageNetworkManager;
    //}
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn put_radio_into_mesh(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    try set_radio_down(io, allocator);
    try set_ad_hoc_mode(io, allocator);
    try set_radio_up(io, allocator);
    try mesh_join(io, allocator);
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn set_radio_down(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    const run_command = try std.process.run(
        allocator,
        io, 
        .{
            .argv = &.{
                "ip",
                "link",
                "set",
                "wlan0",
                "down",
            }
        }
    );
    defer {
        allocator.free(run_command.stderr);
        allocator.free(run_command.stdout);
    }

    // The command has failed - let's let the user know the details before
    // returning an err state
    if (false == run_command.term.success()) {
        std.log.err("Error turning radio off", .{});
        std.log.info("\tstdout for command: \"{s}\"", .{ run_command.stdout });
        std.log.info("\tstderr for command: \"{s}\"", .{ run_command.stderr });
        var backing_buffer_stderr : [256]u8 = undefined;
        var stderr_writer = std.Io.File.writer(
            .stderr(),
            io,
            &backing_buffer_stderr,
        );
        try run_command.term.format(&stderr_writer.interface);
        try stderr_writer.end();
        return error.CouldNotTurnRadioOff;
    }
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn set_ad_hoc_mode(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    const run_command = try std.process.run(
        allocator,
        io, 
        .{
            .argv = &.{
                "iw",
                "dev",
                "wlan0",
                "set",
                "type",
                "ibss",
            }
        }
    );
    defer {
        allocator.free(run_command.stderr);
        allocator.free(run_command.stdout);
    }

    // The command has failed - let's let the user know the details before
    // returning an err state
    if (false == run_command.term.success()) {
        std.log.err("Error setting ad-hoc mode", .{});
        std.log.info("\tstdout for command: \"{s}\"", .{ run_command.stdout });
        std.log.info("\tstderr for command: \"{s}\"", .{ run_command.stderr });
        var backing_buffer_stderr : [256]u8 = undefined;
        var stderr_writer = std.Io.File.writer(
            .stderr(),
            io,
            &backing_buffer_stderr,
        );
        try run_command.term.format(&stderr_writer.interface);
        try stderr_writer.end();
        return error.CouldNotTurnRadioIntoAdHoc;
    }
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn set_radio_up(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    const run_command = try std.process.run(
        allocator,
        io, 
        .{
            .argv = &.{
                "ip",
                "link",
                "set",
                "wlan0",
                "up",
            }
        }
    );
    defer {
        allocator.free(run_command.stderr);
        allocator.free(run_command.stdout);
    }

    // The command has failed - let's let the user know the details before
    // returning an err state
    if (false == run_command.term.success()) {
        std.log.err("Error turning radio on", .{});
        std.log.info("\tstdout for command: \"{s}\"", .{ run_command.stdout });
        std.log.info("\tstderr for command: \"{s}\"", .{ run_command.stderr });
        var backing_buffer_stderr : [256]u8 = undefined;
        var stderr_writer = std.Io.File.writer(
            .stderr(),
            io,
            &backing_buffer_stderr,
        );
        try run_command.term.format(&stderr_writer.interface);
        try stderr_writer.end();
        return error.CouldNotTurnRadioOn;
    }
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn mesh_join(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    const run_command = try std.process.run(
        allocator,
        io, 
        .{
            .argv = &.{
                "iw",
                "dev",
                "wlan0",
                "ibss",
                "join",
                "zigcam-mesh",
                "2412",
            }
        }
    );
    defer {
        allocator.free(run_command.stderr);
        allocator.free(run_command.stdout);
    }

    // The command has failed - let's let the user know the details before
    // returning an err state
    if (false == run_command.term.success()) {
        std.log.err("Error joining the mesh", .{});
        std.log.info("\tstdout for command: \"{s}\"", .{ run_command.stdout });
        std.log.info("\tstderr for command: \"{s}\"", .{ run_command.stderr });
        var backing_buffer_stderr : [256]u8 = undefined;
        var stderr_writer = std.Io.File.writer(
            .stderr(),
            io,
            &backing_buffer_stderr,
        );
        try run_command.term.format(&stderr_writer.interface);
        try stderr_writer.end();
        return error.CouldNotJoinTheMesh;
    }
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn put_radio_into_client(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    try set_radio_down(io, allocator);
    try set_managed_mode(io, allocator);
    try set_radio_up(io, allocator);
}


//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
fn set_managed_mode(
    io : std.Io,
    allocator : std.mem.Allocator,
) !void {
    const run_command = try std.process.run(
        allocator,
        io, 
        .{
            .argv = &.{
                "sudo",
                "iw",
                "dev",
                "wlan0",
                "set",
                "type",
                "managed",
            }
        }
    );
    defer {
        allocator.free(run_command.stderr);
        allocator.free(run_command.stdout);
    }

    // The command has failed - let's let the user know the details before
    // returning an err state
    if (false == run_command.term.success()) {
        std.log.err("Error make radio managed", .{});
        std.log.info("\tstdout for command: \"{s}\"", .{ run_command.stdout });
        std.log.info("\tstderr for command: \"{s}\"", .{ run_command.stderr });
        var backing_buffer_stderr : [256]u8 = undefined;
        var stderr_writer = std.Io.File.writer(
            .stderr(),
            io,
            &backing_buffer_stderr,
        );
        try run_command.term.format(&stderr_writer.interface);
        try stderr_writer.end();
        return error.CouldNotSetRadioToManagedMode;
    }
}
















//******************************************************************************
//* Function:    
//*
//* Description: 
//******************************************************************************
