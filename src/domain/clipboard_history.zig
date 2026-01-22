const std = @import("std");
const item_mod = @import("clipboard_item.zig");

const Id = item_mod.Id;
const ClipboardItem = item_mod.ClipboardItem;

pub const ClipboardHistory = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(ClipboardItem),
    max_items: usize,

    pub fn init(allocator: std.mem.Allocator, max_items: usize) ClipboardHistory {
        std.debug.assert(max_items > 0);
        return .{
            .allocator = allocator,
            .items = std.ArrayList(ClipboardItem).init(allocator),
            .max_items = max_items,
        };
    }

    pub fn deinit(self: *ClipboardHistory) void {
        self.items.deinit();
    }

    fn findIndex(self: *ClipboardHistory, id: Id) ?usize {
        for (self.items.items, 0..) |it, idx| {
            if (std.mem.eql(u8, &it.id, &id)) return idx;
        }
        return null;
    }

    pub fn len(self: *ClipboardHistory) usize {
        return self.items.items.len;
    }

    pub fn add(self: *ClipboardHistory, item: ClipboardItem) !void {
        if (self.findIndex(item.id)) |idx| {
            _ = self.items.orderedRemove(idx);
        }
        try self.items.insert(0, item);
        if (self.items.items.len > self.max_items) {
            _ = self.items.pop();
        }
    }

    pub fn remove(self: *ClipboardHistory, id: Id) bool {
        if (self.findIndex(id)) |idx| {
            _ = self.items.orderedRemove(idx);
            return true;
        }
        return false;
    }

    pub fn at(self: *ClipboardHistory, idx: usize) ClipboardItem {
        return self.items.items[idx];
    }

    pub fn slice(self: *ClipboardHistory) []const ClipboardItem {
        return self.items.items;
    }
};

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;

fn makeItem(id_byte: u8, ts: i128, text: []const u8) ClipboardItem {
    const id: Id = .{id_byte} ** 16;
    return ClipboardItem.init(id, ts, text) catch unreachable;
}

test "adds newest first and caps capacity" {
    var history = ClipboardHistory.init(std.testing.allocator, 2);
    defer history.deinit();

    try history.add(makeItem(1, 1, "one"));
    try history.add(makeItem(2, 2, "two"));
    try history.add(makeItem(3, 3, "three"));

    try expectEqual(@as(usize, 2), history.len());
    try expectEqualStrings("three", history.at(0).text());
    try expectEqualStrings("two", history.at(1).text());
}

test "deduplicates by id and keeps latest" {
    var history = ClipboardHistory.init(std.testing.allocator, 3);
    defer history.deinit();

    try history.add(makeItem(1, 1, "old"));
    try history.add(makeItem(2, 2, "other"));
    try history.add(makeItem(1, 3, "new"));

    try expectEqual(@as(usize, 2), history.len());
    try expectEqualStrings("new", history.at(0).text());
    try expectEqualStrings("other", history.at(1).text());
}

test "remove deletes by id" {
    var history = ClipboardHistory.init(std.testing.allocator, 3);
    defer history.deinit();

    try history.add(makeItem(9, 1, "x"));
    try history.add(makeItem(8, 2, "y"));

    try expect(history.remove(.{9} ** 16));
    try expectEqual(@as(usize, 1), history.len());
    try expectEqualStrings("y", history.at(0).text());
    try expect(!history.remove(.{7} ** 16));
}
