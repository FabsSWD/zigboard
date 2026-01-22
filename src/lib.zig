pub const domain = struct {
    const item = @import("domain/clipboard_item.zig");
    const session = @import("domain/session.zig");
    const history = @import("domain/clipboard_history.zig");

    pub const Id = item.Id;
    pub const Timestamp = item.Timestamp;
    pub const ClipboardItem = item.ClipboardItem;
    pub const Session = session.Session;
    pub const ClipboardHistory = history.ClipboardHistory;
};
