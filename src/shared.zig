const std = @import("std");

pub const stdout = std.io.getStdOut().writer();
pub const stderr = std.io.getStdErr().writer();
