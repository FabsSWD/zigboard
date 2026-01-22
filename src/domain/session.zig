const std = @import("std");
const ClipboardTypes = @import("clipboard_item.zig");

pub const Id = ClipboardTypes.Id;
pub const Timestamp = ClipboardTypes.Timestamp;

pub const Session = struct {
    id: Id,
    started_at: Timestamp,

    pub fn init(id: Id, started_at: Timestamp) !Session {
        if (started_at < 0) return error.InvalidTimestamp;

        return Session{
            .id = id,
            .started_at = started_at,
        };
    }

    pub fn initRandom(random: anytype, started_at: Timestamp) !Session {
        var id: Id = undefined;
        random.bytes(&id);
        return init(id, started_at);
    }

    pub fn idBytes(self: Session) Id {
        return self.id;
    }

    pub fn startedAt(self: Session) Timestamp {
        return self.started_at;
    }
};

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

const FakeRand = struct {
    buf: Id,
    pub fn bytes(self: *FakeRand, out: []u8) void {
        @memcpy(out, self.buf[0..out.len]);
    }
};

test "init rejects negative timestamp" {
    const id: Id = .{0} ** 16;
    try expectError(error.InvalidTimestamp, Session.init(id, -1));
}

test "initRandom uses provided rng bytes" {
    const seed: Id = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    var rng = FakeRand{ .buf = seed };
    const started: Timestamp = 42;

    const session = try Session.initRandom(&rng, started);
    try expectEqualSlices(u8, &seed, &session.idBytes());
    try expectEqual(started, session.startedAt());
}

test "init stores provided id" {
    const id: Id = .{ 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 };
    const started: Timestamp = 123;
    const session = try Session.init(id, started);
    try expectEqualSlices(u8, &id, &session.idBytes());
    try expectEqual(started, session.startedAt());
}
