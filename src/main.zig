const lib = @import("root.zig");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer stdout.flush() catch {};
    var stderr = std.io.bufferedWriter(std.io.getStdErr().writer());
    defer stderr.flush() catch {};
    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next();
    const arg_flags = enum {
        @"-o",
    };
    const arg_flags_map = lib.string_map_to_enum(arg_flags);
    var arg = args.next();
    var input: ?std.io.BufferedReader(4096, std.io.AnyReader) = null;
    var output: ?std.io.BufferedWriter(4096, std.io.AnyWriter) = null;
    while (arg != null) : (arg = args.next()) {
        const flag = arg_flags_map.get(arg.?);
        if (flag != null) {
            switch (flag.?) {
                .@"-o" => {
                    const output_path = args.next();
                    if (output_path == null) {
                        _ = try stderr.write("-o flag supplied but no output path given");
                        return;
                    }
                    output = std.io.bufferedWriter((try std.fs.cwd().createFile(
                        output_path.?,
                        std.fs.File.CreateFlags{},
                    )).writer().any());
                },
            }
        } else {
            input = std.io.bufferedReader((try std.fs.cwd().openFile(
                arg.?,
                std.fs.File.OpenFlags{
                    .mode = .read_only,
                },
            )).reader().any());
        }
    }
    if (input == null) {
        input = std.io.bufferedReader(std.io.getStdIn().reader().any());
    }
    if (output == null) {
        output = std.io.bufferedWriter(std.io.getStdOut().writer().any());
    }
    try lib.compile(input.?.reader().any(), output.?.writer().any(), stderr.writer().any(), allocator);
    try output.?.flush();
}
