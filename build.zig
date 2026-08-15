const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const calculated_cpu_count = std.Thread.getCpuCount() catch 3;
    const option_max_threads = b.option(usize, "max_threads", "Set the maximum number of threads for concurrency (min = 3)") orelse @max(calculated_cpu_count, 3);

    if (3 > option_max_threads) {
        return error.ThreadCountTooLow;
    }

    const options = b.addOptions();
    options.addOption(usize, "max_threads", option_max_threads);

    const mod_auth = b.createModule(.{
        .root_source_file = b.path("src/auth/root_auth.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_config = b.createModule(.{
        .root_source_file = b.path("src/config/root_config.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "auth", .module = mod_auth },
        },
    });

    const mod_complex_stream = b.createModule(.{
        .root_source_file = b.path("src/global/structs/complexStream/root_complex_stream.zig"),
        .target = target,
        .optimize = optimize,
    });


    const mod_system_ops = b.createModule(.{
        .root_source_file = b.path("src/systemOps/root_systemOps.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "complexStream", .module = mod_complex_stream },
            .{ .name = "config", .module = mod_config },
        },
    });

    const mod_server_ops = b.createModule(.{
        .root_source_file = b.path("src/serverOps/root_serverOps.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "complexStream", .module = mod_complex_stream },
            .{ .name = "sysOps", .module = mod_system_ops },
            //.{ .name = "config", .module = mod_config },
            .{ .name = "auth", .module = mod_auth },
        },
    });

    const mod_threads = b.createModule(.{
        .root_source_file = b.path("src/threads/root_threads.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = mod_config },
            .{ .name = "complexStream", .module = mod_complex_stream },
            .{ .name = "serverOps", .module = mod_server_ops },
        },
    });

    const exe = b.addExecutable(.{
        .name = "home_security_server_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = mod_config },
                .{ .name = "serverOps", .module = mod_server_ops },
                .{ .name = "threads", .module = mod_threads },
                .{ .name = "auth", .module = mod_auth },
            },
        }),
    });

    exe.root_module.addOptions("options", options);
    exe.root_module.link_libc = true;

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();
}
