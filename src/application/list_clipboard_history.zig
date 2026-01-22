const domain = @import("../lib.zig").domain;

const ClipboardHistory = domain.ClipboardHistory;
const ClipboardItem = domain.ClipboardItem;

pub const ListClipboardHistory = struct {
    history: *const ClipboardHistory,

    pub const Output = struct {
        items: []const ClipboardItem,
    };

    pub fn init(history: *const ClipboardHistory) ListClipboardHistory {
        return .{ .history = history };
    }

    pub fn execute(self: *const ListClipboardHistory) Output {
        return .{ .items = self.history.slice() };
    }
};

const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// Helper to create item
const item_mod = @import("../domain/clipboard_item.zig");
const Id = item_mod.Id;
const Timestamp = item_mod.Timestamp;

fn makeItem(id_byte: u8, ts: Timestamp, text: []const u8) item_mod.ClipboardItem {
    const id: Id = .{id_byte} ** 16;
    return item_mod.ClipboardItem.init(id, ts, text) catch unreachable;
}

test "returns items in deterministic newest-first order" {
    var history = ClipboardHistory.init(std.testing.allocator, 3);
    defer history.deinit();

    try history.add(makeItem(1, 1, "one"));
    try history.add(makeItem(2, 2, "two"));

    var uc = ListClipboardHistory.init(&history);
    const out = uc.execute();

    try expectEqual(@as(usize, 2), out.items.len);
    try expectEqualStrings("two", out.items[0].text());
    try expectEqualStrings("one", out.items[1].text());
}
