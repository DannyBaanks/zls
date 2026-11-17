const std = @import("std");

pub fn main() void {}

comptime {
    const probe: u32 = "type error on purpose";
    _ = probe;
}
