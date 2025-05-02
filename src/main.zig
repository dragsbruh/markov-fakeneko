const std = @import("std");
const shared = @import("./shared.zig");

const Model = @import("./model.zig").Model;
const Modelfile = @import("./model.zig").Modelfile;
const ModelTrainer = @import("./model.zig").ModelTrainer;
const ModelGenerator = @import("./model.zig").ModelGenerator;

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("leak detected\n", .{});
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try shared.stderr.print("error: no model metadata file specified\n", .{});
        return 1;
    }

    const model_file_path = args[1];

    var modelfile = try Modelfile.load(allocator, model_file_path);
    defer modelfile.deinit(allocator);

    var model = Model.init(modelfile.config.depth);
    defer model.deinit(allocator);

    var trainer = ModelTrainer.init(&modelfile, &model);
    try trainer.train(allocator, modelfile.config.train_buffer_size, modelfile.config.train_throttle);

    var generator = try ModelGenerator.init(allocator, &model);
    defer generator.deinit(allocator);

    while (try generator.next(allocator, &model)) |byte| {
        try shared.stdout.writeByte(byte);
        std.Thread.sleep(modelfile.config.gen_throttle);
    }

    try shared.stdout.writeByte('\n');

    return 0;
}
