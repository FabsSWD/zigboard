const std = @import("std");

pub const LinuxClipboard = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LinuxClipboard {
        return .{ .allocator = allocator };
    }

    pub fn read(self: *LinuxClipboard) ![]const u8 {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "xclip", "-o", "-selection", "clipboard" },
        });
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            self.allocator.free(result.stdout);
            return error.ClipboardReadFailed;
        }

        return result.stdout;
    }

    pub fn free(self: *LinuxClipboard, data: []const u8) void {
        self.allocator.free(data);
    }
};

const expectError = std.testing.expectError;
const expect = std.testing.expect;

test "init creates adapter" {
    const adapter = LinuxClipboard.init(std.testing.allocator);
    try expect(adapter.allocator.ptr == std.testing.allocator.ptr);
}
