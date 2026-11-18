//! ISY: end-to-end tests for the `isy/*` agent request extensions.
//! They drive the real message path (`sendJsonMessageSync` → `processMessage`)
//! so the wire format is exactly what an agent client would see.

const std = @import("std");
const zls = @import("zls");

const Context = @import("../context.zig").Context;

const allocator: std.mem.Allocator = std.testing.allocator;

/// Sends one `isy/*` request over the JSON-RPC wire and returns the parsed response.
fn isyRequest(context: *Context, method: []const u8, params_json: []const u8) !std.json.Parsed(std.json.Value) {
    const json_message = try std.fmt.allocPrint(allocator, "{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"{s}\",\"params\":{s}}}", .{ method, params_json });
    defer allocator.free(json_message);

    const response_json = try context.server.sendJsonMessageSync(json_message) orelse return error.NoResponse;
    defer allocator.free(response_json);

    return std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
}

fn expectStr(expected: []const u8, value: std.json.Value) !void {
    try std.testing.expectEqualStrings(expected, value.string);
}

fn expectBool(expected: bool, value: std.json.Value) !void {
    try std.testing.expect(expected == value.bool);
}

fn expectUint(expected: i64, value: std.json.Value) !void {
    try std.testing.expectEqual(expected, value.integer);
}

fn expectNull(value: std.json.Value) !void {
    try std.testing.expect(std.meta.activeTag(value) == .null);
}

test "isy/fileOutline" {
    var context: Context = try .init();
    defer context.deinit();

    const uri = try context.addDocument(.{
        .source =
        \\pub const S = struct {
        \\    value: u32,
        \\    pub fn get(self: S) u32 {
        \\        return self.value;
        \\    }
        \\};
        \\
        \\const top = 1;
        \\
        \\fn helper() void {}
        \\
    ,
    });

    const uri_params = try std.fmt.allocPrint(allocator, "{{\"textDocument\":{{\"uri\":\"{s}\"}}}}", .{uri.raw});
    defer allocator.free(uri_params);

    var response = try isyRequest(&context, "isy/fileOutline", uri_params);
    defer response.deinit();

    const result = response.value.object.get("result").?;
    const declarations = result.object.get("declarations").?.array.items;

    try std.testing.expectEqual(@as(usize, 5), declarations.len);

    // pub const S = struct { ... }
    const decl_s = declarations[0].object;
    try expectStr("Constant", decl_s.get("kind").?);
    try expectStr("S", decl_s.get("name").?);
    try expectBool(true, decl_s.get("is_pub").?);
    try std.testing.expect(decl_s.get("container") == null);
    try expectUint(0, decl_s.get("line").?);

    // value: u32
    const decl_value = declarations[1].object;
    try expectStr("Field", decl_value.get("kind").?);
    try expectStr("value", decl_value.get("name").?);
    try expectStr("S", decl_value.get("container").?);

    // pub fn get(self: S) u32
    const decl_get = declarations[2].object;
    try expectStr("Function", decl_get.get("kind").?);
    try expectStr("get", decl_get.get("name").?);
    try expectStr("S", decl_get.get("container").?);
    try expectBool(true, decl_get.get("is_pub").?);
    const signature = decl_get.get("signature").?.string;
    try std.testing.expect(std.mem.startsWith(u8, signature, "fn get(self: S)"));
    try std.testing.expect(std.mem.endsWith(u8, signature, "u32"));

    // const top = 1 and fn helper()
    const decl_top = declarations[3].object;
    try expectStr("Constant", decl_top.get("kind").?);
    try expectStr("top", decl_top.get("name").?);
    try expectBool(false, decl_top.get("is_pub").?);

    const decl_helper = declarations[4].object;
    try expectStr("Function", decl_helper.get("kind").?);
    try expectStr("helper", decl_helper.get("name").?);
    try expectBool(false, decl_helper.get("is_pub").?);
}

test "isy/fileOutline for an unopened document" {
    var context: Context = try .init();
    defer context.deinit();

    var response = try isyRequest(&context, "isy/fileOutline", "{\"textDocument\":{\"uri\":\"untitled://Untitled-999.zig\"}}");
    defer response.deinit();

    // The request fails cleanly with `RequestFailed` instead of crashing.
    const err = response.value.object.get("error").?;
    try expectUint(@intFromEnum(zls.lsp.types.LSPErrorCodes.RequestFailed), err.object.get("code").?);
}

test "isy/diagnosticsSummary" {
    var context: Context = try .init();
    defer context.deinit();

    // `generateDiagnostics` only publishes when the client subscribed to
    // `textDocument/publishDiagnostics`; opt in like a real diagnostics client.
    context.server.client_capabilities.supports_publish_diagnostics = true;

    // clean document: nothing to report
    _ = try context.addDocument(.{
        .source =
        \\const ok = 1;
        \\
    ,
    });

    var empty = try isyRequest(&context, "isy/diagnosticsSummary", "{}");
    defer empty.deinit();
    try expectUint(0, empty.value.object.get("result").?.object.get("total").?);

    // broken document: one syntax error
    const broken = try context.addDocument(.{
        .source =
        \\const foo
        \\
    ,
    });
    try zls.diagnostics.generateDiagnostics(context.server, context.server.document_store.getHandle(broken).?);

    var response = try isyRequest(&context, "isy/diagnosticsSummary", "{}");
    defer response.deinit();

    const result = response.value.object.get("result").?;
    try expectUint(1, result.object.get("file_count").?);
    try expectUint(1, result.object.get("total").?);
    try expectUint(1, result.object.get("errors").?);

    const files = result.object.get("files").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), files.len);
    try expectStr(broken.raw, files[0].object.get("uri").?);
}

test "isy/agentState" {
    var context: Context = try .init();
    defer context.deinit();

    var response = try isyRequest(&context, "isy/agentState", "{}");
    defer response.deinit();

    const result = response.value.object.get("result").?;
    try expectStr("initialized", result.object.get("status").?);
    try expectBool(std.process.can_spawn and !@import("builtin").single_threaded, result.object.get("build_on_save_supported").?);
    try expectUint(4, result.object.get("max_nested_build_projects").?);
    try std.testing.expectEqual(@as(usize, 0), result.object.get("workspaces").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 0), result.object.get("nested_build_projects").?.array.items.len);
}

test "unknown isy/ request answers null" {
    var context: Context = try .init();
    defer context.deinit();

    var response = try isyRequest(&context, "isy/doesNotExist", "{}");
    defer response.deinit();

    try expectNull(response.value.object.get("result").?);
    try std.testing.expect(response.value.object.get("error") == null);
}

test "unknown custom (non-isy) request still answers null" {
    var context: Context = try .init();
    defer context.deinit();

    var response = try isyRequest(&context, "someVendor/customMethod", "{}");
    defer response.deinit();

    try expectNull(response.value.object.get("result").?);
}