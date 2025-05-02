const std = @import("std");

pub fn shiftLeft(sequence: []u8, end: u8) void {
    if (sequence.len == 0) return;
    if (sequence.len > 1) {
        for (0..sequence.len - 1) |i| {
            sequence[i] = sequence[i + 1];
        }
    }
    sequence[sequence.len - 1] = end;
}

pub fn emptyAlloc(allocator: std.mem.Allocator, size: anytype) ![]u8 {
    const actual_size: usize = @intCast(size);
    const buffer = try allocator.alloc(u8, actual_size);
    @memset(buffer, 0);
    return buffer;
}
