const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "zigboard",
        .root_module = root_module,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zigboard",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("zigboard", root_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the daemon");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = root_module,
    });

    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.step.dependOn(&unit_tests.step);
    b.step("test", "Run unit tests").dependOn(&run_tests.step);

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&lib.step);
}
