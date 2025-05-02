const std = @import("std");
const utils = @import("utils.zig");
const Node = @import("./node.zig").Node;

pub const Model = struct {
    /// each node is a sequence -> node hashmap
    nodes: std.StringHashMapUnmanaged(Node) = .empty,
    depth: u32,

    pub fn init(depth: u32) Model {
        return Model{
            .depth = depth,
        };
    }

    /// this "trains" the markov chain and returns the last sequence it was trained on
    /// avoid calling this super frequently like for every word and stuff, because it allocates every call
    /// optionally returned sequence can be submitted to `Model.markSequenceEnd` to... mark ends of statements, sentences etc.
    pub fn train(self: *Model, allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
        const sequence = try utils.emptyAlloc(allocator, self.depth);

        var currentNode = try self.getNode(allocator, sequence);
        for (bytes) |byte| {
            try currentNode.incrementWeight(allocator, byte);
            utils.shiftLeft(sequence, byte);
            currentNode = try self.getNode(allocator, sequence);
        }

        return sequence;
    }

    /// marks sequence to be the ending sequence, what did you expect
    /// completely optional, avoid if you want infinite generation (which is not always guaranteed, btw)
    pub fn markSequenceEnd(self: *Model, allocator: std.mem.Allocator, sequence: []const u8) !void {
        var node = try self.getNode(allocator, sequence);
        try node.incrementWeight(allocator, 0);
    }

    /// gets node corresponding to given sequence, or creates one if not found
    pub fn getNode(self: *Model, allocator: std.mem.Allocator, sequence: []const u8) !*Node {
        if (self.nodes.getPtr(sequence)) |ptr| {
            return ptr;
        } else {
            const key = try allocator.dupe(u8, sequence);
            const new_entry = try self.nodes.getOrPutValue(allocator, key, Node{});
            return new_entry.value_ptr;
        }
    }

    pub fn deinit(self: *Model, allocator: std.mem.Allocator) void {
        var iter = self.nodes.iterator();

        while (iter.next()) |node| {
            allocator.free(node.key_ptr.*);
            node.value_ptr.deinit(allocator);
        }

        self.nodes.deinit(allocator);
    }
};

pub const ModelGenerator = struct {
    sequence: []u8,

    pub fn init(allocator: std.mem.Allocator, model: *Model) !ModelGenerator {
        return ModelGenerator{ .sequence = try utils.emptyAlloc(allocator, model.depth) };
    }

    pub fn deinit(self: *ModelGenerator, allocator: std.mem.Allocator) void {
        allocator.free(self.sequence);
    }

    pub fn next(self: *ModelGenerator, allocator: std.mem.Allocator, model: *Model) !?u8 {
        const node = try model.getNode(allocator, self.sequence);
        if (node.weights.items.len == 0) {
            for (0..model.depth) |i| {
                self.sequence[i] = 0;
            }
            // allocator.free(self.sequence);
            // self.sequence = try utils.emptyAlloc(allocator, model.depth);
            return try self.next(allocator, model);
        }

        const next_char_index = std.crypto.random.weightedIndex(usize, node.weights.items);
        const next_char = node.chars.items[next_char_index];

        if (next_char == 0) return null;

        utils.shiftLeft(self.sequence, next_char);
        return next_char;
    }
};

pub const ModelMetadata = struct {
    depth: u32,
    files: []const []const u8,
    train_throttle: u64,
    gen_throttle: u64,
    model_bin: []const u8,
    train_buffer_size: usize,
};

pub const Modelfile = struct {
    config: ModelMetadata,
    files: std.ArrayListUnmanaged([]u8) = .empty,

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Modelfile {
        const raw = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
        defer allocator.free(raw);

        var raw_sentinel: [:0]u8 = try allocator.allocSentinel(u8, raw.len, 0);
        defer allocator.free(raw_sentinel);

        @memcpy(raw_sentinel[0..raw.len], raw);

        var arena = std.heap.ArenaAllocator.init(allocator);
        const ar_allocator = arena.allocator();
        defer arena.deinit();

        const model_data = try std.zon.parse.fromSlice(ModelMetadata, ar_allocator, raw_sentinel, null, .{});

        var self = Modelfile{
            .config = model_data,
            .files = .empty,
        };

        var cwd = std.fs.cwd();

        for (model_data.files) |file| {
            const stat = try cwd.statFile(file);
            if (stat.kind == .directory) {
                const dir = try cwd.openDir(file, .{ .iterate = true });
                var walker = try dir.walk(allocator);
                defer walker.deinit();

                while (try walker.next()) |entry| {
                    if (entry.kind == .file) {
                        const full_path = try dir.realpathAlloc(allocator, entry.path);
                        try self.files.append(allocator, full_path);
                    }
                }
            } else if (stat.kind == .file) {
                const full_path = try cwd.realpathAlloc(allocator, file);
                try self.files.append(allocator, full_path);
            }
        }

        return self;
    }

    pub fn deinit(self: *Modelfile, allocator: std.mem.Allocator) void {
        for (self.files.items) |item| {
            allocator.free(item);
        }
        self.files.deinit(allocator);
    }
};

pub const ModelTrainer = struct {
    modelfile: *Modelfile,
    model: *Model,

    pub fn init(modelfile: *Modelfile, model: *Model) ModelTrainer {
        return ModelTrainer{
            .model = model,
            .modelfile = modelfile,
        };
    }

    pub fn train(self: *ModelTrainer, allocator: std.mem.Allocator, buffer_size: usize, throttle: u64) !void {
        const text = try std.fmt.allocPrint(allocator, "training with depth {d}", .{self.modelfile.config.depth});
        defer allocator.free(text);

        const progress = std.Progress.start(.{
            .root_name = text,
            .estimated_total_items = self.modelfile.files.items.len,
        });

        const buffer = try allocator.alloc(u8, buffer_size);
        defer allocator.free(buffer);

        for (self.modelfile.files.items) |file_path| {
            const stat = try std.fs.cwd().statFile(file_path);
            const file = try std.fs.cwd().openFile(file_path, .{});

            const child_progress_node = progress.start(std.fs.path.basename(file_path), stat.size);

            var total_read: usize = 0;

            while (true) {
                const read = try file.read(buffer);
                if (read == 0) break;

                const seq = try self.model.train(allocator, buffer);
                allocator.free(seq);

                total_read += read;
                child_progress_node.setCompletedItems(total_read);

                if (throttle > 0) std.Thread.sleep(throttle);
            }

            child_progress_node.end();
        }

        progress.end();
    }
};
