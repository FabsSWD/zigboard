const std = @import("std");

pub const Id = [16]u8;
pub const Timestamp = i128;

pub const ClipboardItem = struct {
    id: Id,
    created_at: Timestamp,
    payload: []const u8,

    pub fn init(id: Id, created_at: Timestamp, payload: []const u8) !ClipboardItem {
        if (created_at < 0) return error.InvalidTimestamp;
        if (payload.len == 0) return error.EmptyPayload;

        return ClipboardItem{
            .id = id,
            .created_at = created_at,
            .payload = payload,
        };
    }

    pub fn idBytes(self: ClipboardItem) Id {
        return self.id;
    }

    pub fn createdAt(self: ClipboardItem) Timestamp {
        return self.created_at;
    }

    pub fn text(self: ClipboardItem) []const u8 {
        return self.payload;
    }
};

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "init rejects empty payload" {
    var id: Id = undefined;
    @memset(&id, 0);
    try expectError(error.EmptyPayload, ClipboardItem.init(id, 0, ""));
}

test "init rejects negative timestamp" {
    var id: Id = undefined;
    @memset(&id, 1);
    try expectError(error.InvalidTimestamp, ClipboardItem.init(id, -1, "abc"));
}

test "init produces item and accessors work" {
    const id: Id = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    const created_at: Timestamp = 1_735_000_000_000; // arbitrary epoch nanoseconds
    const payload = "hello";

    const item = try ClipboardItem.init(id, created_at, payload);
    try expectEqual(id, item.idBytes());
    try expectEqual(created_at, item.createdAt());
    try expectEqualStrings(payload, item.text());
}
