// node is the most basic item, its a sequence that points to probable next characters in that sequence and their respective weights
const Node = std.AutoHashMapUnmanaged(u8, usize);

const FakeNeko = struct {
    nodes: std.StringHashMapUnmanaged(Node) = .empty,
    depth: u32,

    pub fn get_node(self: *FakeNeko, allocator: std.mem.Allocator, sequence: []const u8) !*Node {
        const existing = self.nodes.getPtr(sequence);
        if (existing) |node| {
            return node;
        }

        const key = try allocator.dupe(u8, sequence);
        errdefer allocator.free(key);

        const node = Node.empty;
        return (try self.nodes.getOrPutValue(allocator, key, node)).value_ptr;
    }

    pub fn record(self: *FakeNeko, allocator: std.mem.Allocator, bytes: []const u8) !void {
        var currentSequence: []u8 = try allocator.alloc(u8, self.depth);
        defer allocator.free(currentSequence);

        for (0..self.depth) |i| currentSequence[i] = 0;

        for (bytes) |byte| {
            try self.incrementWeightTowards(allocator, currentSequence, byte);
            shift(currentSequence, byte);
        }

        try self.incrementWeightTowards(allocator, currentSequence, 0);
    }

    pub fn generate(self: *FakeNeko, allocator: std.mem.Allocator, max_length: usize) ![]const u8 {
        var currentSequence: []u8 = try allocator.alloc(u8, self.depth);
        defer allocator.free(currentSequence);

        for (0..self.depth) |i| currentSequence[i] = 0;

        var output: []u8 = try allocator.alloc(u8, max_length);
        errdefer allocator.free(output);

        var node = try self.get_node(allocator, currentSequence);
        for (0..max_length) |i| {
            if (node.*.count() == 0) {
                if (i == 0) return output;
                output = try allocator.realloc(output, i);
                return output;
            }

            const result = try decomposeNode(allocator, node);
            defer allocator.free(result.chars);
            defer allocator.free(result.weights);

            const next_char_index = std.crypto.random.weightedIndex(usize, result.weights);
            const next_char = result.chars[next_char_index];

            if (next_char == 0) {
                output = try allocator.realloc(output, i);
                return output;
            }

            output[i] = next_char;
            shift(currentSequence, next_char);
            node = try self.get_node(allocator, currentSequence);
        }

        return output;
    }

    pub fn decomposeNode(allocator: std.mem.Allocator, node: *Node) !struct { chars: []const u8, weights: []const usize } {
        var chars = try allocator.alloc(u8, node.count());
        errdefer allocator.free(chars);
        var weights = try allocator.alloc(usize, node.count());
        errdefer allocator.free(weights);

        var iter = node.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| {
            chars[i] = entry.key_ptr.*;
            weights[i] = entry.value_ptr.*;
            i += 1;
        }

        return .{
            .chars = chars,
            .weights = weights,
        };
    }

    pub fn incrementWeightTowards(self: *FakeNeko, allocator: std.mem.Allocator, sequence: []const u8, char: u8) !void {
        const node = try self.get_node(allocator, sequence);

        const weight = try node.getOrPutValue(allocator, char, 0);
        weight.value_ptr.* += 1;
    }

    pub fn deinit(self: *FakeNeko, allocator: std.mem.Allocator) void {
        var iter = self.nodes.iterator();

        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(allocator);
        }

        self.nodes.deinit(allocator);
    }

    fn shift(seq: []u8, end: u8) void {
        if (seq.len == 0) return;
        if (seq.len == 1) {
            seq[0] = end;
            return;
        }

        for (0..seq.len - 1) |i| {
            seq[i] = seq[i + 1];
        }
        seq[seq.len - 1] = end;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer {
        const leaked = gpa.detectLeaks();
        if (leaked) std.debug.print("leaks detected\n", .{});
    }

    const allocator = gpa.allocator();

    var fneko = FakeNeko{
        .depth = 2,
    };

    try fneko.record(allocator, "abcd");

    const text = try fneko.generate(allocator, 100);
    defer allocator.free(text);

    std.debug.print("{s}\ninfo: size = {d}\n", .{ text, text.len });

    defer fneko.deinit(allocator);
}

const std = @import("std");
