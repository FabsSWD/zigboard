const std = @import("std");

const Id = @import("../lib.zig").domain.Id;
const Timestamp = @import("../lib.zig").domain.Timestamp;

pub const WebhookNotifier = struct {
    allocator: std.mem.Allocator,
    url: []const u8,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !WebhookNotifier {
        const owned = try allocator.dupe(u8, url);
        return .{ .allocator = allocator, .url = owned };
    }

    pub fn deinit(self: *WebhookNotifier) void {
        self.allocator.free(self.url);
    }

    pub fn notifyAdded(self: *WebhookNotifier, id: Id, ts: Timestamp, text: []const u8) !void {
        var body_buf = std.ArrayList(u8){};
        defer body_buf.deinit(self.allocator);
        const w = body_buf.writer(self.allocator);

        try w.writeAll("{\"event\":\"clipboard_added\",\"id\":\"");
        try writeHex(&w, &id);
        try w.writeAll("\",\"ts\":");
        try w.print("{d}", .{ts});
        try w.writeAll(",\"text\":\"");
        try writeJsonString(&w, text);
        try w.writeAll("\"}");

        const body = try body_buf.toOwnedSlice(self.allocator);
        defer self.allocator.free(body);
        try self.postJson(body);
    }

    pub fn notifyDeleted(self: *WebhookNotifier, id: Id) !void {
        var body_buf = std.ArrayList(u8){};
        defer body_buf.deinit(self.allocator);
        const w = body_buf.writer(self.allocator);

        try w.writeAll("{\"event\":\"clipboard_deleted\",\"id\":\"");
        try writeHex(&w, &id);
        try w.writeAll("\"}");

        const body = try body_buf.toOwnedSlice(self.allocator);
        defer self.allocator.free(body);
        try self.postJson(body);
    }

    fn postJson(self: *WebhookNotifier, body: []const u8) !void {
        // Use curl for simplicity; assumes it's available in PATH.
        const args = &[_][]const u8{
            "curl",
            "-sS",
            "-X",
            "POST",
            "-H",
            "Content-Type: application/json",
            "-d",
            body,
            self.url,
        };
        const res = try std.process.Child.run(.{ .allocator = self.allocator, .argv = args });
        defer self.allocator.free(res.stdout);
        defer self.allocator.free(res.stderr);
        // Don't treat non-zero exit strictly fatal; surface as error.
        if (res.term.Exited != 0) return error.WebhookFailed;
    }
};

fn writeHex(w: anytype, bytes: []const u8) !void {
    for (bytes) |b| try w.print("{x:0>2}", .{b});
}

fn writeJsonString(w: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => try w.writeByte(c),
        }
    }
}
