const std = @import("std");

pub fn build(b: *std.Build) !void {
    // const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("gherkin", .{
        .source_file = .{ .path = "src/main.zig" },
    });

    // const static_gherkin = b.addStaticLibrary(.{
    //     .name = "gherkin",
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const step_static_gherkin = b.step("lib-static", "Build the static gherkin library");
    // step_static_gherkin.dependOn(&static_gherkin.step);

    // const install_static_gherkin = b.addInstallArtifact(static_gherkin, .{});
    // step_static_gherkin.dependOn(&install_static_gherkin.step);

    const test_gherkin = b.addTest(.{
        .name = "gherkin-test",
        .root_source_file = .{ .path = "src/main.zig" },
    });

    const step_test = b.step("test", "Run gherkin library tests");
    step_test.dependOn(&b.addRunArtifact(test_gherkin).step);

    // const step_install = b.getInstallStep();
    // step_install.dependOn(step_static_gherkin);
}
