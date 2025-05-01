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

    pub fn record(self: *FakeNeko, allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
        var currentSequence: []u8 = try allocator.alloc(u8, self.depth);

        for (0..self.depth) |i| currentSequence[i] = 0;

        for (bytes) |byte| {
            try self.incrementWeightTowards(allocator, currentSequence, byte);
            shift(currentSequence, byte);
        }

        return currentSequence;
    }

    pub fn markRecordEndAt(self: *FakeNeko, allocator: std.mem.Allocator, sequence: []const u8) !void {
        try self.incrementWeightTowards(allocator, sequence, 0);
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
};

const Command = enum { train, generate, serve, build, help };

const EndType = enum { no_end, newline, doublenewline, word, sentence };
const BUFFER_SIZE = 4096;

pub fn streamingTrainer(fneko: *FakeNeko, allocator: std.mem.Allocator, file: std.fs.File, end_type: EndType) !void {
    var last_byte: ?u8 = null;
    var last_sequence: ?[]const u8 = null;

    defer {
        if (last_sequence) |seq| {
            allocator.free(seq);
        }
    }

    while (true) {
        var buffer: [BUFFER_SIZE]u8 = undefined;
        var bytes_read = try file.read(&buffer);
        if (bytes_read == 0) break;

        if (end_type == .doublenewline) {
            if (last_byte == '\n' and buffer[0] == '\n') {
                bytes_read -= 1;
                shift(&buffer, 0);
                last_byte = null;
                try fneko.markRecordEndAt(allocator, last_sequence orelse unreachable);
            }

            if (buffer[bytes_read - 1] == '\n') {
                bytes_read -= 1;
                last_byte = '\n';
            }
        }

        if (end_type != .no_end) {
            const delimiter: []const u8 = switch (end_type) {
                .doublenewline => "\n\n",
                .newline => "\n",
                .sentence => ".",
                .word => " ",
                else => unreachable,
            };

            var parts = std.mem.splitSequence(u8, &buffer, delimiter);
            while (parts.next()) |part| {
                if (part.len > 0) {
                    if (last_sequence) |seq| {
                        allocator.free(seq);
                    }
                    last_sequence = try fneko.record(allocator, part);
                    try fneko.markRecordEndAt(allocator, last_sequence orelse unreachable);
                }
            }
        } else {
            if (last_sequence) |seq| {
                allocator.free(seq);
            }
            last_sequence = try fneko.record(allocator, &buffer);
        }
    }

    if (end_type == .no_end) {
        try fneko.markRecordEndAt(allocator, last_sequence orelse unreachable);
    }
}

pub fn main() !u8 {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try stderr.print("error: please specify command\n", .{});
        return try printUsage(args[0]);
    }

    const command_str = args[1];
    const command_args = args[2..];

    const command = std.meta.stringToEnum(Command, command_str) orelse {
        try stderr.print("error: specified command \"{s}\" does not exist\n", .{command_str});
        return 1;
    };

    return switch (command) {
        Command.help => printUsage(args[0]),
        Command.train => commandTrain(command_args, allocator),
        Command.generate => commandGenerate(command_args, allocator),
        Command.build => commandBuild(command_args, allocator),
        Command.serve => commandServe(command_args, allocator),
    };
}

fn commandTrain(args: []const []const u8, allocator: std.mem.Allocator) !u8 {
    if (args.len < 3) {
        try stderr.print("error: incorrect usage of \"train\"\n", .{});
        try stderr.print("usage: train <model_file> <end_type> <depth> [...input_files]\n", .{});
        return 1;
    } else if (args.len < 4) {
        try stderr.print("error: please specify atleast one input file to train\n", .{});
        return 1;
    }

    const model_file = args[0];
    const end_type_str = args[1];
    const depth_str = args[2];

    const end_type = std.meta.stringToEnum(EndType, end_type_str) orelse {
        try stderr.print("error: incorrect end_type specified - \"{s}\"\n", .{end_type_str});
        try stderr.print("available end types are: no_end, newline, doublenewline\n", .{});
        return 1;
    };

    const depth = std.fmt.parseInt(u32, depth_str, 10) catch {
        try stderr.print("error: incorrect depth specified - \"{s}\"\n", .{depth_str});
        try stderr.print("depth should be a number\n", .{});
        return 1;
    };

    const input_files = args[3..];

    for (input_files) |file| {
        std.fs.cwd().access(file, .{}) catch {
            try stderr.print("error: input file {s} is not accessible from current working directory\n", .{file});
            return 1;
        };
    }

    var fneko = FakeNeko{ .depth = depth };
    defer fneko.deinit(allocator);

    try stdout.print("training {s} with depth {d} and end type {s}\n", .{ model_file, depth, @tagName(end_type) });

    for (input_files) |file_path| {
        const file = try std.fs.cwd().openFile(file_path, .{});

        try streamingTrainer(&fneko, allocator, file, end_type);
    }

    const text = try fneko.generate(allocator, 1000);
    defer allocator.free(text);
    try stdout.print("{s}\n", .{text});

    return 0;
}

fn commandGenerate(_: []const []const u8, _: std.mem.Allocator) !u8 {
    return 0;
}

fn commandBuild(_: []const []const u8, _: std.mem.Allocator) !u8 {
    return 0;
}

fn commandServe(_: []const []const u8, _: std.mem.Allocator) !u8 {
    return 0;
}

fn printUsage(executable: []const u8) !u8 {
    try stdout.print(
        \\usage: {s} <command> [...args] [--no-throttle]
        \\
        \\commands:
        \\  train       <model_file> <end_type> <depth> [...input_files]
        \\              trains a model using input files and saves to model_file
        \\              end_type options:
        \\                  no_end     - disables end detection
        \\                  newline    - ends on each newline
        \\                  doublenewline - ends on double newline
        \\
        \\  generate    <model_file> [max_length]
        \\              generates text using the given model file
        \\
        \\  build
        \\              trains using config from fneko.zon
        \\
    , .{executable});
    return 1;
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

const std = @import("std");

pub const stdout = std.io.getStdOut().writer();
pub const stderr = std.io.getStdErr().writer();
