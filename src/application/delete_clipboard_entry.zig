const std = @import("std");
const domain = @import("../lib.zig").domain;

const Id = domain.Id;
const ClipboardHistory = domain.ClipboardHistory;

pub const DeleteClipboardEntry = struct {
    history: *ClipboardHistory,

    pub fn init(history: *ClipboardHistory) DeleteClipboardEntry {
        return .{ .history = history };
    }

    pub fn execute(self: *DeleteClipboardEntry, id: Id) !void {
        if (!self.history.remove(id)) {
            return error.EntryNotFound;
        }
    }
};

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;

const item_mod = @import("../domain/clipboard_item.zig");
const ClipboardItem = item_mod.ClipboardItem;

fn makeItem(id_byte: u8, ts: i128, text: []const u8) ClipboardItem {
    const id: Id = .{id_byte} ** 16;
    return ClipboardItem.init(id, ts, text) catch unreachable;
}

test "removes entry when present" {
    var history = ClipboardHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    try history.add(makeItem(1, 1, "first"));
    try history.add(makeItem(2, 2, "second"));

    var uc = DeleteClipboardEntry.init(&history);
    try uc.execute(.{1} ** 16);

    try expectEqual(@as(usize, 1), history.len());
}

test "returns error when entry not found" {
    var history = ClipboardHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    try history.add(makeItem(1, 1, "only"));

    var uc = DeleteClipboardEntry.init(&history);
    try expectError(error.EntryNotFound, uc.execute(.{99} ** 16));

    try expectEqual(@as(usize, 1), history.len());
}
