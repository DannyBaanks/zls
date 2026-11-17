//! Fixture: no "check" step, exe is installed and runnable, and a test artifact shares the root file.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{ .name = "fixture", .root_module = mod });
    b.installArtifact(exe);
    b.step("run", "Run the fixture").dependOn(&b.addRunArtifact(exe).step);
    const tests = b.addTest(.{ .root_module = mod });
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(tests).step);
}
