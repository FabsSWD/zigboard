const std = @import("std");
const LinuxClipboard = @import("linux_clipboard.zig").LinuxClipboard;

pub fn ClipboardListener(comptime OnChange: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        clipboard: LinuxClipboard,
        on_change: OnChange,
        last_content: ?[]const u8,
        running: bool,

        pub fn init(allocator: std.mem.Allocator, on_change: OnChange) Self {
            return .{
                .allocator = allocator,
                .clipboard = LinuxClipboard.init(allocator),
                .on_change = on_change,
                .last_content = null,
                .running = false,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.last_content) |content| {
                self.allocator.free(content);
            }
        }

        pub fn start(self: *Self) void {
            self.running = true;
        }

        pub fn stop(self: *Self) void {
            self.running = false;
        }

        pub fn poll(self: *Self) !void {
            if (!self.running) return;

            const content = self.clipboard.read() catch |err| {
                if (err == error.ClipboardReadFailed) return;
                return err;
            };
            defer self.clipboard.free(content);

            const changed = blk: {
                if (self.last_content) |last| {
                    if (std.mem.eql(u8, last, content)) break :blk false;
                    self.allocator.free(last);
                }
                break :blk true;
            };

            if (changed) {
                self.last_content = try self.allocator.dupe(u8, content);
                try self.on_change.onChange(content);
            }
        }
    };
}

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const TestHandler = struct {
    call_count: usize = 0,
    last_content: []const u8 = "",

    pub fn onChange(self: *TestHandler, content: []const u8) !void {
        self.call_count += 1;
        self.last_content = content;
    }
};

test "listener starts and stops" {
    var handler = TestHandler{};
    var listener = ClipboardListener(*TestHandler).init(std.testing.allocator, &handler);
    defer listener.deinit();

    try expect(!listener.running);
    listener.start();
    try expect(listener.running);
    listener.stop();
    try expect(!listener.running);
}

test "poll does nothing when stopped" {
    var handler = TestHandler{};
    var listener = ClipboardListener(*TestHandler).init(std.testing.allocator, &handler);
    defer listener.deinit();

    try listener.poll();
    try expectEqual(@as(usize, 0), handler.call_count);
}
