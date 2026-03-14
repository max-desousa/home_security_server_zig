const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const calculated_cpu_count = std.Thread.getCpuCount() catch 3;
    const option_max_threads = b.option(usize, "max_threads", "Set the maximum number of threads for concurrency (min = 3)") orelse calculated_cpu_count;

    if (3 > option_max_threads) {
        return error.ThreadCountTooLow;
    }

    const options = b.addOptions();
    options.addOption(usize, "max_threads", option_max_threads);

    const mod_complex_stream = b.createModule(.{
        .root_source_file = b.path("src/net/complexStream/root_complex_stream.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_debug = b.createModule(.{
        .root_source_file = b.path("src/debug/root_debug.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_parser = b.createModule(.{
        .root_source_file = b.path("src/parser/root_parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "debug", .module = mod_debug },
            .{ .name = "complexStream", .module = mod_complex_stream },
        },
    });

    const mod_req = b.createModule(.{
        .root_source_file = b.path("src/req/root_req.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_resources = b.createModule(.{
        .root_source_file = b.path("src/resources/root_resources.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "resources", .module = mod_req },
        },
    });

    const mod_serve = b.createModule(.{
        .root_source_file = b.path("src/serve/root_serve.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "request", .module = mod_req },
            .{ .name = "resources" , .module = mod_resources },
        }
    });

    const mod_config = b.createModule(.{
        .root_source_file = b.path("src/config/root_config.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_threads = b.createModule(.{
        .root_source_file = b.path("src/threads/root_threads.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = mod_config },
            .{ .name = "debug", .module = mod_debug },
            .{ .name = "parser", .module = mod_parser },
            .{ .name = "complexStream", .module = mod_complex_stream },
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
                .{ .name = "requests", .module = mod_req },
                .{ .name = "serve", .module = mod_serve },
                .{ .name = "debug", .module = mod_debug },
                .{ .name = "threads", .module = mod_threads },
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

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
