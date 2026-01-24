const std = @import("std");
const domain = @import("../lib.zig").domain;

const ClipboardItem = domain.ClipboardItem;
const ClipboardHistory = domain.ClipboardHistory;
const Id = domain.Id;
const Timestamp = domain.Timestamp;

pub const AddClipboardEntryInput = struct {
    payload: []const u8,
    timestamp: Timestamp,
};

pub fn AddClipboardEntry(comptime IdGenerator: type) type {
    return struct {
        const Self = @This();

        id_gen: *IdGenerator,
        history: *ClipboardHistory,

        pub fn init(id_gen: *IdGenerator, history: *ClipboardHistory) Self {
            return .{
                .id_gen = id_gen,
                .history = history,
            };
        }

        pub fn execute(self: *Self, input: AddClipboardEntryInput) !void {
            const id = self.id_gen.generate();

            // Duplicate payload so the item owns its bytes; clipboard buffers are freed after polling.
            const payload_copy = try self.history.allocator.dupe(u8, input.payload);
            const item = try ClipboardItem.init(id, input.timestamp, payload_copy);
            try self.history.add(item);
        }
    };
}

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const FakeIdGen = struct {
    counter: u8 = 1,

    pub fn generate(self: *FakeIdGen) Id {
        const id: Id = .{self.counter} ** 16;
        self.counter +%= 1;
        return id;
    }
};

test "adds entry to history with generated id" {
    var gen = FakeIdGen{};
    var history = ClipboardHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    var use_case = AddClipboardEntry(FakeIdGen).init(&gen, &history);

    try use_case.execute(.{ .payload = "hello", .timestamp = 100 });

    try expectEqual(@as(usize, 1), history.len());
    const item = history.at(0);
    try expectEqualStrings("hello", item.text());
    try expectEqual(@as(Timestamp, 100), item.createdAt());
}

test "suppresses duplicates via history aggregate" {
    var gen = FakeIdGen{};
    var history = ClipboardHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    var use_case = AddClipboardEntry(FakeIdGen).init(&gen, &history);

    try use_case.execute(.{ .payload = "first", .timestamp = 1 });
    try use_case.execute(.{ .payload = "second", .timestamp = 2 });

    gen.counter = 1;
    try use_case.execute(.{ .payload = "duplicate", .timestamp = 3 });

    try expectEqual(@as(usize, 2), history.len());
    try expectEqualStrings("duplicate", history.at(0).text());
}
