const std = @import("std");
const domain = @import("../lib.zig").domain;

const Session = domain.Session;
const Timestamp = domain.Timestamp;

pub const SessionRegistry = struct {
    allocator: std.mem.Allocator,
    current: ?Session = null,

    pub fn init(allocator: std.mem.Allocator) SessionRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SessionRegistry) void {
        _ = self;
    }

    pub fn register(self: *SessionRegistry, session: Session) void {
        self.current = session;
    }

    pub fn getCurrent(self: *SessionRegistry) ?Session {
        return self.current;
    }
};

pub const InitializeSession = struct {
    registry: *SessionRegistry,
    random: std.Random,

    pub fn init(registry: *SessionRegistry, random: std.Random) InitializeSession {
        return .{ .registry = registry, .random = random };
    }

    pub fn execute(self: *InitializeSession, started_at: Timestamp) !Session {
        const session = try Session.initRandom(self.random, started_at);
        self.registry.register(session);
        return session;
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const FakeRandom = struct {
    value: u8,

    pub fn random(self: *FakeRandom) std.Random {
        return std.Random.init(self, fill);
    }

    fn fill(self: *FakeRandom, buf: []u8) void {
        @memset(buf, self.value);
    }
};

test "registers new session with random id" {
    var fake_rng = FakeRandom{ .value = 42 };
    var registry = SessionRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var use_case = InitializeSession.init(&registry, fake_rng.random());
    const session = try use_case.execute(1000);

    try expectEqual(@as(Timestamp, 1000), session.startedAt());

    const registered = registry.getCurrent();
    try expect(registered != null);
    try expectEqual(@as(Timestamp, 1000), registered.?.startedAt());

    const expected_id = [_]u8{42} ** 16;
    try expectEqual(expected_id, session.idBytes());
}

test "replaces previous session" {
    var fake_rng = FakeRandom{ .value = 7 };
    var registry = SessionRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var use_case = InitializeSession.init(&registry, fake_rng.random());

    _ = try use_case.execute(100);
    fake_rng.value = 99;
    const second = try use_case.execute(200);

    const current = registry.getCurrent();
    try expect(current != null);
    try expectEqual(@as(Timestamp, 200), current.?.startedAt());
    try expectEqual(second.idBytes(), current.?.idBytes());
}
