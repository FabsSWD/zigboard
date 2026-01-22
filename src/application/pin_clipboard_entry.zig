const std = @import("std");
const domain = @import("../lib.zig").domain;

const Id = domain.Id;

pub const PinClipboardEntry = struct {
    map: std.AutoHashMap(Id, void),

    pub fn init(allocator: std.mem.Allocator) PinClipboardEntry {
        return .{ .map = std.AutoHashMap(Id, void).init(allocator) };
    }

    pub fn deinit(self: *PinClipboardEntry) void {
        self.map.deinit();
    }

    pub fn pin(self: *PinClipboardEntry, id: Id) !void {
        _ = try self.map.getOrPut(id);
    }

    pub fn unpin(self: *PinClipboardEntry, id: Id) bool {
        return self.map.fetchRemove(id) != null;
    }

    pub fn isPinned(self: *PinClipboardEntry, id: Id) bool {
        return self.map.contains(id);
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

fn idFromByte(b: u8) Id {
    return .{b} ** 16;
}

test "pin is idempotent" {
    var uc = PinClipboardEntry.init(std.testing.allocator);
    defer uc.deinit();

    const id = idFromByte(1);
    try uc.pin(id);
    try uc.pin(id);

    try expect(uc.isPinned(id));
    try expectEqual(@as(usize, 1), uc.map.count());
}

test "unpin removes when present" {
    var uc = PinClipboardEntry.init(std.testing.allocator);
    defer uc.deinit();

    const id = idFromByte(2);
    try uc.pin(id);

    try expect(uc.unpin(id));
    try expect(!uc.isPinned(id));
}

test "unpin returns false if absent" {
    var uc = PinClipboardEntry.init(std.testing.allocator);
    defer uc.deinit();

    const id = idFromByte(3);
    try expect(!uc.unpin(id));
}
