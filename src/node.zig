const std = @import("std");

/// node is the most fundamental object and is supposed to be represented by a sequence of characters
pub const Node = struct {
    /// for optimization reasons we store the index of weights instead of actual weight
    /// it might not make much sense to do so while training but while running we dont want to allocate thousands of times just to free immediately
    /// might make it optional during training but meh
    char_weight_map: std.AutoHashMapUnmanaged(u8, usize) = .empty,
    chars: std.ArrayListUnmanaged(u8) = .empty,
    weights: std.ArrayListUnmanaged(usize) = .empty,

    /// increments the weight of a character wrt this sequence
    pub fn incrementWeight(self: *Node, allocator: std.mem.Allocator, character: u8) !void {
        const index_entry = try self.char_weight_map.getOrPut(allocator, character);
        if (index_entry.found_existing) {
            self.weights.items[index_entry.value_ptr.*] += 1;
        } else {
            index_entry.value_ptr.* = self.weights.items.len; // since usize has default zero value
            try self.weights.append(allocator, 1);
            try self.chars.append(allocator, character);
        }
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        self.char_weight_map.deinit(allocator);
        self.weights.deinit(allocator);
        self.chars.deinit(allocator);
    }
};
