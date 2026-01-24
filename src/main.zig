const std = @import("std");
const zigboard = @import("zigboard");

const domain = zigboard.domain;
const application = zigboard.application;
const adapters = zigboard.adapters;
const ipc = zigboard.ipc;
const infrastructure = zigboard.infrastructure;

const ClipboardHistory = domain.ClipboardHistory;
const AddClipboardEntry = application.AddClipboardEntry;
const ListClipboardHistory = application.ListClipboardHistory;
const PinClipboardEntry = application.PinClipboardEntry;
const DeleteClipboardEntry = zigboard.DeleteClipboardEntry;
const InitializeSession = application.InitializeSession;
const SessionRegistry = application.SessionRegistry;
const FilePersistence = adapters.FilePersistence;
const WebhookNotifier = adapters.WebhookNotifier;
const LinuxClipboard = adapters.LinuxClipboard;
const ClipboardListener = adapters.ClipboardListener;
const HistoryQueryHandler = ipc.HistoryQueryHandler;
const CommandHandler = ipc.CommandHandler;
const LocalHttpServer = ipc.LocalHttpServer;
const Daemon = infrastructure.Daemon;

// Global pointer to current context for isPinned callback
var global_pinner: ?*PinClipboardEntry = null;

fn isPinnedCb(id: domain.Id) bool {
    if (global_pinner) |pinner| {
        return pinner.isPinned(id);
    }
    return false;
}

const IdGenerator = struct {
    random: std.Random,
    pub fn generate(self: *IdGenerator) domain.Id {
        var id: domain.Id = undefined;
        self.random.bytes(&id);
        return id;
    }
};

const AppContext = struct {
    allocator: std.mem.Allocator,
    history: ClipboardHistory,
    pinner: PinClipboardEntry,
    deleter: DeleteClipboardEntry,
    lister: ListClipboardHistory,
    adder: AddClipboardEntry(IdGenerator),
    server: LocalHttpServer(*AppContext),
    clipboard: LinuxClipboard,
    persistence: FilePersistence,
    registry: SessionRegistry,
    id_gen: IdGenerator,
    last_clipboard_content: ?[]const u8,
    webhook: ?WebhookNotifier = null,

    pub fn init(allocator: std.mem.Allocator) !AppContext {
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        const random = prng.random();

        var history = ClipboardHistory.init(allocator, 1000);
        errdefer history.deinit();

        var pinner_temp = PinClipboardEntry.init(allocator);
        errdefer pinner_temp.deinit();

        const clipboard = LinuxClipboard.init(allocator);

        const id_gen = IdGenerator{ .random = random };

        var registry = SessionRegistry.init(allocator);
        errdefer registry.deinit();

        var session_init = InitializeSession.init(&registry, random);
        _ = try session_init.execute(std.time.nanoTimestamp());

        const persistence = FilePersistence.init(allocator, "clipboard_history.json");

        var loaded_pers = @constCast(&persistence);
        var loaded = try loaded_pers.load();
        for (loaded.items) |item| {
            try history.add(item);
        }
        loaded.deinit(allocator);

        var server = try LocalHttpServer(*AppContext).init(allocator, 8080, undefined);
        errdefer server.deinit();

        // Create and return the context - handlers will be set in main() after struct is stable
        return AppContext{
            .allocator = allocator,
            .history = history,
            .pinner = pinner_temp, // temporary
            .deleter = undefined, // will be set in main() after struct is stable
            .lister = undefined, // will be set in main() after struct is stable
            .adder = undefined, // will be set in main() after struct is stable
            .server = server,
            .clipboard = clipboard,
            .persistence = persistence,
            .registry = registry,
            .id_gen = id_gen,
            .last_clipboard_content = null,
            .webhook = null,
        };
    }

    pub fn handleRequest(self: *AppContext, req: []const u8) ![]const u8 {
        // Set global pinner for callback
        global_pinner = &self.pinner;
        defer global_pinner = null;
        
        // Route to appropriate handler
        if (std.mem.indexOf(u8, req, "GET /history") != null) {
            var lister_copy = self.lister;
            var query_handler = HistoryQueryHandler.init(self.allocator, &lister_copy, &isPinnedCb);
            return query_handler.handle(req);
        }
        var command_handler = CommandHandler.init(self.allocator, &self.history, &self.pinner, &self.deleter);
        command_handler.onDeleted = &onDeletedCb;
        command_handler.onDeletedCtx = self;
        return command_handler.handle(req);
    }

    pub fn deinit(self: *AppContext) void {
        if (self.last_clipboard_content) |content| {
            self.allocator.free(content);
        }
        self.server.deinit();
        self.registry.deinit();
        self.registry.deinit();
        self.pinner.deinit();
        self.history.deinit();
    }
};

const Router = struct {
    allocator: std.mem.Allocator,
    query_handler: HistoryQueryHandler,
    command_handler: CommandHandler,

    pub fn handle(self: *Router, req: []const u8) ![]const u8 {
        if (std.mem.indexOf(u8, req, "GET /history") != null) {
            return self.query_handler.handle(req);
        }
        return self.command_handler.handle(req);
    }
};

fn tick(ctx_ptr: *anyopaque) !void {
    var ctx: *AppContext = @ptrCast(@alignCast(ctx_ptr));
    
    // Poll clipboard for changes
    const content = ctx.clipboard.read() catch |err| blk: {
        if (err == error.ClipboardReadFailed) break :blk null;
        return err;
    };
    
    if (content) |new_content| {
        defer ctx.clipboard.free(new_content);
        
        // Skip empty clipboard content
        if (new_content.len == 0) {
            try ctx.server.acceptOnce();
            return;
        }
        
        const changed = if (ctx.last_clipboard_content) |last|
            !std.mem.eql(u8, last, new_content)
        else
            true;
        
        if (changed) {
            // Free old content
            if (ctx.last_clipboard_content) |last| {
                ctx.allocator.free(last);
            }
            
            // Save new content
            ctx.last_clipboard_content = try ctx.allocator.dupe(u8, new_content);
            
            // Add to history (use owned duplicate as source)
            const timestamp = std.time.nanoTimestamp();
            try ctx.adder.execute(.{
                .payload = ctx.last_clipboard_content.?,
                .timestamp = timestamp,
            });

            // Notify webhook if configured
            if (ctx.webhook) |*wh| {
                const item = ctx.history.at(0);
                wh.notifyAdded(item.id, item.created_at, item.payload) catch |err| {
                    std.debug.print("Webhook notify add failed: {}\n", .{err});
                };
            }
        }
    }
    
    try ctx.server.acceptOnce();
}

fn onStart(ctx_ptr: *anyopaque) !void {
    const ctx: *AppContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.server.start();
    std.debug.print("Zigboard daemon started on http://127.0.0.1:8080\n", .{});
    std.debug.print("Open ui/index.html in your browser\n", .{});
}

fn onStop(ctx_ptr: *anyopaque) void {
    const ctx: *AppContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.server.stop();
    
    const items = ctx.history.slice();
    ctx.persistence.save(items) catch |err| {
        std.debug.print("Failed to save history: {}\n", .{err});
    };
    
    std.debug.print("Zigboard daemon stopped\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = try AppContext.init(allocator);
    defer ctx.deinit();

    // Now that ctx is in its final location, set up self-referential pointers
    ctx.deleter = DeleteClipboardEntry.init(&ctx.history);
    ctx.lister = ListClipboardHistory.init(&ctx.history);
    ctx.adder = AddClipboardEntry(IdGenerator).init(&ctx.id_gen, &ctx.history);

    // Set the handler to point to the context now that ctx has a stable address
    ctx.server.handler = &ctx;

    // Configure webhook from environment if present
    if (std.process.getEnvVarOwned(allocator, "ZIGBOARD_WEBHOOK_URL")) |url| {
        defer allocator.free(url);
        ctx.webhook = WebhookNotifier.init(allocator, url) catch null;
    } else |_| {}

    var daemon = Daemon.init(allocator, .{
        .tick = tick,
        .on_start = onStart,
        .on_stop = onStop,
        .ctx = &ctx,
        .idle_ns = 500 * std.time.ns_per_ms,
    });

    try daemon.run();
}

fn onDeletedCb(ctx_ptr: *anyopaque, id: domain.Id) void {
    const ctx: *AppContext = @ptrCast(@alignCast(ctx_ptr));
    if (ctx.webhook) |*wh| {
        wh.notifyDeleted(id) catch |err| {
            std.debug.print("Webhook notify delete failed: {}\n", .{err});
        };
    }
}
