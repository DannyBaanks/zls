//! ISY: agent-oriented LSP extensions served under the `isy/` method prefix.
//!
//! Standard LSP clients never call these; they exist for AI agents that drive
//! ZLS programmatically (the ISyCo multi-agent bridge, `opencode`, Codex, ...).
//! Every handler is additive: it reads existing state and reshapes it, it does
//! not change how ZLS behaves for human editors.
//!
//! - `isy/fileOutline`: flat list of declarations with signatures and line spans
//! - `isy/diagnosticsSummary`: counts by severity + files, worst first
//! - `isy/agentState`: which projects have build-on-save watchers + config

const std = @import("std");
const lsp = @import("lsp");
const types = lsp.types;
const Server = @import("../Server.zig");
const Uri = @import("../Uri.zig");
const document_symbol = @import("document_symbol.zig");
const log = std.log.scoped(.agent);

const BuildOnSaveSupport = @import("../build_runner/shared.zig").BuildOnSaveSupport;

pub const Error = error{ Canceled, OutOfMemory, InvalidParams, RequestFailed };

/// All ISY custom request methods start with this prefix.
pub const method_prefix = "isy/";

/// Returns whether `method` belongs to this module (even if unknown here).
pub fn isIsyMethod(method: []const u8) bool {
    return std.mem.startsWith(u8, method, method_prefix);
}

/// Dispatch an `isy/*` request. Returns `null` for unknown methods in the prefix
/// (the caller answers `null`, the JSON-RPC result for "nothing to say").
pub fn handleIsyRequest(server: *Server, arena: std.mem.Allocator, request: lsp.MethodWithParams) Error!?std.json.Value {
    if (std.mem.eql(u8, request.method, "isy/fileOutline")) {
        return try fileOutline(server, arena, request.params);
    } else if (std.mem.eql(u8, request.method, "isy/diagnosticsSummary")) {
        return try diagnosticsSummary(server, arena, request.params);
    } else if (std.mem.eql(u8, request.method, "isy/agentState")) {
        return try agentState(server, arena, request.params);
    }
    // Unknown `isy/*` methods answer `null` like any other unsupported custom
    // method; only surface it when debugging the client side.
    log.debug("unknown isy request method '{s}'", .{request.method});
    return null;
}

/// `isy/fileOutline` — params: `{ "textDocument": { "uri": "file:///..." } }`.
///
/// Flattens the hierarchical document symbols into a list an agent can plan an
/// edit from without reading the whole file:
/// `{ "uri": ..., "declarations": [ { "kind": "Function", "name": "f",
///   "signature": "fn f() void", "line": 1, "end_line": 3, "container": "S",
///   "is_pub": true } ] }`
///
/// `signature` reuses the same rendering as `textDocument/documentSymbol`'s
/// `detail` field (for functions: params and return type). `container` is the
/// dotted path of enclosing containers (`""` at top level, omitted when empty).
/// `is_pub` is a heuristic: it looks for a `pub` token before the declaration
/// name on its line. It is correct for `zig fmt`-formatted code, which is what
/// this fork targets.
fn fileOutline(server: *Server, arena: std.mem.Allocator, params: ?std.json.Value) Error!std.json.Value {
    const params_value = params orelse return error.InvalidParams;
    const parsed = std.json.parseFromValueLeaky(types.DocumentSymbol.Params, arena, params_value, .{ .ignore_unknown_fields = true }) catch
        return error.InvalidParams;

    const document_uri = Uri.parse(arena, parsed.textDocument.uri) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidParams,
    };

    // `getOrLoadHandle` reads the file from disk when it was never opened in an
    // editor: an agent should be able to outline any workspace file without a
    // `didOpen` round trip first.
    const handle = try server.document_store.getOrLoadHandle(document_uri) orelse return error.RequestFailed;

    var declarations: std.json.Array = try .initCapacity(arena, 0);
    if (handle.tree.mode == .zon) {
        // `documentSymbol` has no ZON symbol support; answer the uniform shape.
        var root: std.json.ObjectMap = .empty;
        try root.put(arena, "uri", .{ .string = document_uri.raw });
        try root.put(arena, "declarations", .{ .array = declarations });
        return .{ .object = root };
    }

    const symbols = try document_symbol.getDocumentSymbols(arena, &handle.tree, server.offset_encoding);

    try flattenSymbols(arena, &declarations, symbols, handle.tree.source, "");

    var root: std.json.ObjectMap = .empty;
    try root.put(arena, "uri", .{ .string = document_uri.raw });
    try root.put(arena, "declarations", .{ .array = declarations });
    return .{ .object = root };
}

fn flattenSymbols(
    arena: std.mem.Allocator,
    out: *std.json.Array,
    symbols: []const types.DocumentSymbol,
    source: []const u8,
    container: []const u8,
) Error!void {
    for (symbols) |symbol| {
        var fields: std.json.ObjectMap = .empty;
        try fields.put(arena, "kind", .{ .string = @tagName(symbol.kind) });
        try fields.put(arena, "name", .{ .string = symbol.name });
        if (container.len != 0) try fields.put(arena, "container", .{ .string = container });

        // `detail` holds the function signature for callables, and unrelated
        // strings (e.g. a guessed container name) for everything else.
        switch (symbol.kind) {
            .Function, .Method, .Constructor => if (symbol.detail) |signature| {
                try fields.put(arena, "signature", .{ .string = signature });
            },
            else => {},
        }

        try fields.put(arena, "line", .{ .integer = @intCast(symbol.range.start.line) });
        try fields.put(arena, "end_line", .{ .integer = @intCast(symbol.range.end.line) });
        try fields.put(arena, "is_pub", .{ .bool = isPubHeuristic(source, symbol.selectionRange) });

        try out.append(.{ .object = fields });

        const children = symbol.children orelse &.{};
        const child_container = if (children.len == 0) container else blk: {
            break :blk if (container.len == 0)
                symbol.name
            else
                try std.fmt.allocPrint(arena, "{s}.{s}", .{ container, symbol.name });
        };
        try flattenSymbols(arena, out, children, source, child_container);
    }
}

/// Heuristic `pub` detection: the tokens before the declaration name on its
/// line contain the keyword `pub`. Assumes ASCII text before the name (true for
/// `zig fmt`-formatted Zig in practice; the character offset is clamped so
/// multibyte content can only make it *more* conservative).
fn isPubHeuristic(source: []const u8, selection_range: types.Range) bool {
    const line_bytes = lineSlice(source, selection_range.start.line) orelse return false;
    const name_start = @min(@as(usize, selection_range.start.character), line_bytes.len);
    var tokenizer = std.mem.tokenizeAny(u8, line_bytes[0..name_start], " \t\r\n");
    while (tokenizer.next()) |token| {
        if (std.mem.eql(u8, token, "pub")) return true;
    }
    return false;
}

/// Source bytes of the given 0-based line without its newline, or `null`.
fn lineSlice(source: []const u8, line_index: u32) ?[]const u8 {
    var line: usize = 0;
    var start: usize = 0;
    for (source, 0..) |c, index| {
        if (c != '\n') continue;
        if (line == line_index) return source[start..index];
        line += 1;
        start = index + 1;
    }
    if (line == line_index) return source[start..];
    return null;
}

/// `isy/diagnosticsSummary` — params: ignored (may be empty).
///
/// Answers "what is broken right now?" in one request:
/// `{ "file_count": 2, "total": 9, "errors": 9, "warnings": 0,
///    "informations": 0, "hints": 0,
///    "files": [ { "uri": "...", "errors": 9, ... }, ... ] }`
/// Files come first with the most diagnostics. Counts use the exact same
/// collection + deduplication path as `textDocument/publishDiagnostics`.
fn diagnosticsSummary(server: *Server, arena: std.mem.Allocator, params: ?std.json.Value) Error!std.json.Value {
    _ = params;
    const summary = try server.diagnostics_collection.summarizeDiagnostics(arena);

    var files_json: std.json.Array = try .initCapacity(arena, 0);
    for (summary.files) |file| {
        var file_obj: std.json.ObjectMap = .empty;
        try file_obj.put(arena, "uri", .{ .string = file.uri });
        try file_obj.put(arena, "errors", .{ .integer = @intCast(file.errors) });
        try file_obj.put(arena, "warnings", .{ .integer = @intCast(file.warnings) });
        try file_obj.put(arena, "informations", .{ .integer = @intCast(file.informations) });
        try file_obj.put(arena, "hints", .{ .integer = @intCast(file.hints) });
        try files_json.append(.{ .object = file_obj });
    }

    var root: std.json.ObjectMap = .empty;
    try root.put(arena, "file_count", .{ .integer = @intCast(summary.file_count) });
    try root.put(arena, "total", .{ .integer = @intCast(summary.total) });
    try root.put(arena, "errors", .{ .integer = @intCast(summary.errors) });
    try root.put(arena, "warnings", .{ .integer = @intCast(summary.warnings) });
    try root.put(arena, "informations", .{ .integer = @intCast(summary.informations) });
    try root.put(arena, "hints", .{ .integer = @intCast(summary.hints) });
    try root.put(arena, "files", .{ .array = files_json });
    return .{ .object = root };
}

/// `isy/agentState` — params: ignored (may be empty).
///
/// Introspection for agents: which workspace folders have a build-on-save
/// watcher, which nested Zig projects are currently watched (LRU-ordered),
/// the cap, and the effective build-on-save configuration.
fn agentState(server: *Server, arena: std.mem.Allocator, params: ?std.json.Value) Error!std.json.Value {
    _ = params;

    var workspaces_json: std.json.Array = try .initCapacity(arena, 0);
    for (server.workspaces.items) |workspace| {
        try workspaces_json.append(.{ .object = try workspaceStateObject(arena, workspace) });
    }

    var nested_json: std.json.Array = try .initCapacity(arena, 0);
    for (server.nested_build_workspaces.items, 0..) |workspace, index| {
        var workspace_obj = try workspaceStateObject(arena, workspace);
        // least-recently used first, so index 0 is the next to be evicted
        try workspace_obj.put(arena, "lru_index", .{ .integer = @intCast(index) });
        try nested_json.append(.{ .object = workspace_obj });
    }

    const config = &server.config_manager.config;

    var config_json: std.json.ObjectMap = .empty;
    // `null` = not set (default: enabled when the zig version supports watching),
    // `true`/`false` = explicitly enabled/disabled.
    try config_json.put(arena, "enable_build_on_save", if (config.enable_build_on_save) |enabled|
        std.json.Value{ .bool = enabled }
    else
        .null);
    try config_json.put(arena, "build_on_save_args", .{ .integer = @intCast(config.build_on_save_args.len) });
    if (config.zig_exe_path) |zig_exe_path| {
        try config_json.put(arena, "zig_exe_path", .{ .string = zig_exe_path });
    }
    if (config.build_runner_path) |build_runner_path| {
        try config_json.put(arena, "build_runner_path", .{ .string = build_runner_path });
    }

    var root: std.json.ObjectMap = .empty;
    try root.put(arena, "workspaces", .{ .array = workspaces_json });
    try root.put(arena, "nested_build_projects", .{ .array = nested_json });
    try root.put(arena, "max_nested_build_projects", .{ .integer = Server.max_nested_build_workspaces });
    try root.put(arena, "status", .{ .string = @tagName(server.status) });
    try root.put(arena, "build_on_save_supported", .{ .bool = BuildOnSaveSupport.isSupportedComptime() });
    try root.put(arena, "config", .{ .object = config_json });
    return .{ .object = root };
}

fn workspaceStateObject(arena: std.mem.Allocator, workspace: Server.Workspace) Error!std.json.ObjectMap {
    var obj: std.json.ObjectMap = .empty;
    try obj.put(arena, "uri", .{ .string = workspace.uri.raw });

    var has_build_on_save = false;
    var mode: ?[]const u8 = null;
    if (BuildOnSaveSupport.isSupportedComptime()) {
        has_build_on_save = workspace.build_on_save != null;
        mode = if (workspace.build_on_save_mode) |m| @tagName(m) else null;
    }
    try obj.put(arena, "has_build_on_save", .{ .bool = has_build_on_save });
    if (mode) |m| try obj.put(arena, "build_on_save_mode", .{ .string = m });
    return obj;
}