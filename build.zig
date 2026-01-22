const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "zigboard",
        .root_module = root_module,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .root_module = root_module,
    });

    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.step.dependOn(&unit_tests.step);
    b.step("test", "Run unit tests").dependOn(&run_tests.step);

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&lib.step);
}
