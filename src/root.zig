const std = @import("std");
const Instructions = enum {
    @"while",
    @"if",
    @"else",
    end,
    ror,
    rol,
    push,
    pop,
    add,
    sub,
    inc,
    dec,
};
const AOrB = enum { a, b };
const SizedCommand = struct { stack: AOrB, size: usize };
const Condition = struct {
    const ABOr0 = enum { a, b, @"0" };
    const CmpOp = enum { @"<", @">", @"=" };
    lhs: AOrB,
    cmp: CmpOp,
    rhs: ABOr0,
};
const InstructionWithArgs = union(Instructions) {
    @"while": Condition,
    @"if": Condition,
    @"else",
    end,
    ror: SizedCommand,
    rol: SizedCommand,
    push: SizedCommand,
    pop: SizedCommand,
    add: SizedCommand,
    sub: SizedCommand,
    inc: SizedCommand,
    dec: SizedCommand,
};
var saved_byte: ?u8 = null;
var line: u64 = 1;
pub fn string_map_to_enum(comptime T: type) std.static_string_map.StaticStringMap(T) {
    const field_names = @typeInfo(T).@"enum".fields;
    comptime var field_names_corresponding: [field_names.len]struct { @"0": [:0]const u8, @"1": T } = undefined;
    inline for (0..field_names.len) |i| {
        const f = comptime field_names[i].name;
        field_names_corresponding[i].@"0" = f;
        field_names_corresponding[i].@"1" = @field(T, f);
    }
    return std.static_string_map.StaticStringMap(T).initComptime(field_names_corresponding);
}
//always call this before reading in information (in order to handle saved_bit properly).
fn skip_whitespace(input: std.io.AnyReader) !u8 {
    var byte = saved_byte orelse try input.readByte();
    saved_byte = null;
    while (true) {
        switch (byte) {
            ' ', '\t', '\r' => {},
            '\n' => {
                line += 1;
            },
            else => |c| return c,
        }
        byte = try input.readByte();
    }
}
fn interpret_condition(input: std.io.AnyReader, err: std.io.AnyWriter, comptime instruction_name: []const u8) !Condition {
    var condition: Condition = undefined;
    const first_char = skip_whitespace(input) catch {
        try std.fmt.format(err, "\x1b[1;31m{d}: " ++ instruction_name ++ ":\x1b[1;34m expected 'a' or 'b', found EOF\n\x1b[0m", .{line});
        return error.badCharacter;
    };
    condition.lhs = switch (first_char) {
        'a' => .a,
        'b' => .b,
        else => {
            try std.fmt.format(err, "\x1b[1;31m{d}: " ++ instruction_name ++ ":\x1b[1;34m expected 'a' or 'b', found {c}\n\x1b[0m", .{ line, first_char });
            return error.badCharacter;
        },
    };
    const second_char = skip_whitespace(input) catch {
        try std.fmt.format(err, "\x1b[1;31m{d}: " ++ instruction_name ++ " {c}: \x1b[1;34mexpected '>', '=' or '<', found EOF\n\x1b[0m", .{ line, first_char });
        return error.badCharacter;
    };
    condition.cmp = switch (second_char) {
        '>' => .@">",
        '=' => .@"=",
        '<' => .@"<",
        else => {
            try std.fmt.format(err, "\x1b[1;31m{d}: " ++ instruction_name ++ " {c}: \x1b[1;34mexpected '>', '=' or '<', found {c}\n\x1b[0m", .{ line, first_char, second_char });
            return error.badCharacter;
        },
    };
    const third_char = skip_whitespace(input) catch {
        try std.fmt.format(err, "\x1b[1;31m{d}: " ++ instruction_name ++ " {c}: \x1b[1;34mexpected 'a', 'b' or '0', found EOF\n\x1b[0m", .{ line, first_char });
        return error.badCharacter;
    };
    condition.rhs = switch (third_char) {
        'a' => .a,
        'b' => .b,
        '0' => .@"0",
        else => {
            try std.fmt.format(err, "\x1b[1;31m{d}: " ++ instruction_name ++ " {c}: \x1b[1;34mexpected 'a', 'b' or '0', found {c}\n\x1b[0m", .{ line, first_char, third_char });
            return error.badCharacter;
        },
    };
    return condition;
}
fn interpret_sized_command(input: std.io.AnyReader, err: std.io.AnyWriter, comptime instruction_name: []const u8, default_size: usize) !SizedCommand {
    var command: SizedCommand = undefined;
    const first_char = skip_whitespace(input) catch {
        try std.fmt.format(err, "\x1b[1;31m{d}: " ++ instruction_name ++ ": \x1b[1;34mexpected 'a' or 'b', found EOF\n\x1b[0m", .{line});
        return error.badCharacter;
    };
    command.stack = switch (first_char) {
        'a' => .a,
        'b' => .b,
        else => {
            try std.fmt.format(err, "\x1b[1;31m{d}: " ++ instruction_name ++ ": \x1b[1;34mexpected 'a' or 'b', found {c}\n\x1b[0m", .{ line, first_char });
            return error.badCharacter;
        },
    };
    var buf: [20]u8 = undefined;
    buf[0] = skip_whitespace(input) catch {
        command.size = default_size;
        return command;
    };
    if ('0' > buf[0] or '9' < buf[0]) {
        command.size = default_size;
        saved_byte = buf[0];
        return command;
    }
    var buf_written_size: u32 = 1;
    FILL_BUFFER: for (buf[1..]) |*b| {
        b.* = input.readByte() catch break :FILL_BUFFER;
        if ('0' > b.* or '9' < b.*) {
            break :FILL_BUFFER;
        }
        buf_written_size += 1;
    }
    command.size = std.fmt.parseInt(usize, buf[0..buf_written_size], 10) catch {
        try std.fmt.format(err, "\x1b[1;31m{d}: " ++ instruction_name ++ ": Failed to parse integer:\x1b[1;34m found '{s}'\n\x1b[0m", .{ line, buf[0..buf_written_size] });
        return error.parseFailure;
    };
    return command;
}
pub fn compile(input: std.io.AnyReader, output: std.io.AnyWriter, err: std.io.AnyWriter, allocator: std.mem.Allocator) !void {
    var instruction_list = std.ArrayList(InstructionWithArgs).init(allocator);
    defer instruction_list.deinit();
    GET_INSTRUCTIONS: {
        const instructions = string_map_to_enum(Instructions);
        var if_buffer: std.ArrayList(usize) = std.ArrayList(usize).init(allocator);
        defer if_buffer.deinit();
        while (true) {
            var word: [9]u8 = undefined;
            word[0] = skip_whitespace(input) catch break :GET_INSTRUCTIONS;
            if (word[0] != ':') {
                var fbs = std.io.fixedBufferStream(word[1..]);
                try input.streamUntilDelimiter(fbs.writer(), ':', 7);
                _ = fbs.write(":") catch unreachable;
                const instruction: ?Instructions = instructions.get(std.mem.span(@as([*:':']u8, @ptrCast(&word))));
                if (instruction == null) {
                    try std.fmt.format(err, "{d}: unknown instruction {s}\n", .{ line, @as([*:':']u8, @ptrCast(&word)) });
                    return;
                }
                const instruction_with_args: InstructionWithArgs = switch (instruction.?) {
                    .@"if" => IF: {
                        try if_buffer.append(line);
                        const cmp = try interpret_condition(input, err, "if");
                        break :IF .{ .@"if" = cmp };
                    },
                    .@"while" => WHILE: {
                        if_buffer.append(line) catch {};
                        const cmp = try interpret_condition(input, err, "while");
                        if ((cmp.rhs == .a and cmp.lhs == .a) or (cmp.rhs == .b and cmp.lhs == .b)) {
                            try std.fmt.format(err, "\x1b[1;31m{d}: while: cannot compare a stack with itself.\n\x1b[1;34m  The only allowed comparisons are a to b, b to a, a to 0, and b to 0\n\x1b[0m", .{line});
                        }
                        break :WHILE .{ .@"while" = cmp };
                    },
                    .@"else" => .@"else",
                    .end => END: {
                        if (if_buffer.pop() == null) {
                            try std.fmt.format(err, "\x1b[1;31m{d}: end: Unmatched end statement.\n\x1b[1;34m  every end statement must have a corresponding if or while statement.\n\x1b[0m", .{line});
                        }
                        break :END .end;
                    },
                    .pop => .{ .pop = try interpret_sized_command(input, err, "pop", 1) },
                    .push => .{ .push = try interpret_sized_command(input, err, "push", 1) },
                    .add => .{ .add = try interpret_sized_command(input, err, "add", 2) },
                    .sub => .{ .sub = try interpret_sized_command(input, err, "sub", 2) },
                    .dec => .{ .dec = try interpret_sized_command(input, err, "dec", 1) },
                    .inc => .{ .inc = try interpret_sized_command(input, err, "inc", 1) },
                    .ror => .{ .ror = try interpret_sized_command(input, err, "ror", 2) },
                    .rol => .{ .rol = try interpret_sized_command(input, err, "rol", 2) },
                };
                try instruction_list.append(instruction_with_args);
            }
        }
        if (if_buffer.items.len > 0) {
            try std.fmt.format(err, "\x1b[1;31munended if/while statements\x1b[0m \x1b[1;34mon lines ", .{});
            for (if_buffer.items) |i|
                try std.fmt.format(err, "\x1b[1;31m{d}\x1b[0m,", .{i});
            try std.fmt.format(err, "\n\x1b[1;34mPlease add an \x1b[1;32mend:\x1b[1;34m where you would like these to be closed.\x1b[0m\n", .{});
        }
    }
    var ptr_side = AOrB.a;
    var island_len: u64 = 1;
    var a_instruction_raster = std.ArrayList(u8).init(allocator);
    defer a_instruction_raster.deinit();
    var b_instruction_raster = std.ArrayList(u8).init(allocator);
    defer b_instruction_raster.deinit();
    try b_instruction_raster.appendSlice("#,");
    var stack_island_sides = std.ArrayList(AOrB).init(allocator);
    defer stack_island_sides.deinit();
    for (instruction_list.items) |instruction| {
        switch (instruction) {
            inline .push, .pop, .add, .dec, .inc => |instr, tag| {
                var p = instr;
                const raster_instruction: u8 = switch (tag) {
                    .push => 'p',
                    .pop => 'o',
                    .add => 'a',
                    .dec => 'd',
                    .inc => 'i',
                    else => unreachable,
                };
                if (tag == .add) p.size -= 1;
                island_len += p.size;
                try a_instruction_raster.ensureUnusedCapacity(p.size * 2);
                try b_instruction_raster.ensureUnusedCapacity(p.size * 2);
                if (p.stack != ptr_side) {
                    switch (ptr_side) {
                        .a => {
                            a_instruction_raster.appendAssumeCapacity('j');
                            b_instruction_raster.appendAssumeCapacity(raster_instruction);
                        },
                        .b => {
                            a_instruction_raster.appendAssumeCapacity(raster_instruction);
                            b_instruction_raster.appendAssumeCapacity('j');
                        },
                    }
                    a_instruction_raster.appendAssumeCapacity(',');
                    b_instruction_raster.appendAssumeCapacity(',');
                    p.size -= 1;
                    ptr_side = p.stack;
                }
                for (0..p.size) |_| {
                    switch (p.stack) {
                        .a => {
                            a_instruction_raster.appendAssumeCapacity(raster_instruction);
                            b_instruction_raster.appendAssumeCapacity('#');
                        },
                        .b => {
                            a_instruction_raster.appendAssumeCapacity('#');
                            b_instruction_raster.appendAssumeCapacity(raster_instruction);
                        },
                    }
                    a_instruction_raster.appendAssumeCapacity(',');
                    b_instruction_raster.appendAssumeCapacity(',');
                }
            },
            .@"if" => |p| {
                try stack_island_sides.append(p.lhs);
                if (p.lhs != ptr_side) {
                    switch (ptr_side) {
                        .a => {
                            try a_instruction_raster.appendSlice("j,");
                            try b_instruction_raster.appendSlice("#,");
                        },
                        .b => {
                            try a_instruction_raster.appendSlice("#,");
                            try b_instruction_raster.appendSlice("j,");
                        },
                    }
                    island_len += 1;
                }
                if ((p.lhs == .a and p.rhs == .a) or (p.lhs == .b and p.rhs == .b)) {
                    return error.ambiguousComparison;
                }
                if (p.rhs == .@"0") {} else {
                    ptr_side = switch (p.rhs) {
                        .a => .a,
                        .b => .b,
                        else => unreachable,
                    };
                    switch (p.lhs) {
                        .a => {
                            try std.fmt.format(a_instruction_raster.writer(), "j{c},#\x80f\x80#,", .{switch (p.cmp) {
                                .@"<" => @as(u8, '<'),
                                .@"=" => '=',
                                .@">" => '>',
                            }});
                            try std.fmt.format(b_instruction_raster.writer(), "#,#,", .{});
                        },
                        .b => {
                            try std.fmt.format(a_instruction_raster.writer(), "#,#,", .{});
                            try std.fmt.format(b_instruction_raster.writer(), "j{c},#\x80f\x80#,", .{switch (p.cmp) {
                                .@"<" => @as(u8, '<'),
                                .@"=" => '=',
                                .@">" => '>',
                            }});
                        },
                    }
                    island_len += 2;
                }
            },
            .@"else" => {
                const if_side = stack_island_sides.pop().?;
                if (if_side != ptr_side) {
                    switch (ptr_side) {
                        .a => {
                            try a_instruction_raster.appendSlice("j,");
                            try b_instruction_raster.appendSlice("#,");
                        },
                        .b => {
                            try a_instruction_raster.appendSlice("#,");
                            try b_instruction_raster.appendSlice("j,");
                        },
                    }
                    island_len += 1;
                }
                switch (if_side) {
                    .a => {
                        try a_instruction_raster.appendSlice("#\x81#\x81#,");
                        try b_instruction_raster.appendSlice("#\x80f\x80#,");
                    },
                    .b => {
                        try a_instruction_raster.appendSlice("#\x80f\x80#,");
                        try b_instruction_raster.appendSlice("#\x81#\x81#,");
                    },
                }
                island_len += 1;
                try stack_island_sides.append(switch (if_side) {
                    .a => .b,
                    .b => .a,
                });
                ptr_side = if_side;
            },
            .end => {
                const if_side = stack_island_sides.pop().?;
                if (if_side == ptr_side) {
                    switch (ptr_side) {
                        .a => {
                            try a_instruction_raster.appendSlice("j,");
                            try b_instruction_raster.appendSlice("#,");
                        },
                        .b => {
                            try a_instruction_raster.appendSlice("#,");
                            try b_instruction_raster.appendSlice("j,");
                        },
                    }
                    island_len += 1;
                    ptr_side = if_side;
                }
                switch (if_side) {
                    .a => {
                        try a_instruction_raster.appendSlice("#\x81#\x81#,");
                        try b_instruction_raster.appendSlice("#,");
                    },
                    .b => {
                        try b_instruction_raster.appendSlice("#\x81#\x81#,");
                        try a_instruction_raster.appendSlice("#,");
                    },
                }
                island_len += 1;
            },
            else => {},
        }
    }
    try a_instruction_raster.appendSlice("j,");
    var a_width: u32 = 1;
    var max_a_width: u32 = 1;
    var b_width: u32 = 1;
    var max_b_width: u32 = 1;
    for (a_instruction_raster.items) |a| switch (a) {
        '\x80' => {
            a_width += 1;
            if (max_a_width < a_width) max_a_width = a_width;
        },
        '\x81' => {
            a_width -= 1;
        },
        else => {},
    };
    for (b_instruction_raster.items) |b| switch (b) {
        '\x80' => {
            b_width += 1;
            if (max_b_width < b_width) max_b_width = b_width;
        },
        '\x81' => {
            b_width -= 1;
        },
        else => {},
    };
    try output.writeByteNTimes(',', island_len + 2);
    try output.writeByte('\n');
    for (0..max_a_width) |width| {
        const crawl_depth = max_a_width - 1 - width;
        var current_depth: usize = 0;
        try output.writeAll(",#,");
        for (a_instruction_raster.items) |a| switch (a) {
            '\x80' => {
                current_depth += 1;
            },
            '\x81' => {
                current_depth -= 1;
            },
            ',' => {
                try output.writeByte(',');
            },
            else => |byte| {
                if (current_depth == crawl_depth) {
                    try output.writeByte(byte);
                }
            },
        };
        try output.writeByte('\n');
    }
    std.debug.print("{s}\n", .{a_instruction_raster.items});

    try output.writeByteNTimes(',', island_len + 2);
    try output.writeByte('\n');
    for (0..max_b_width) |crawl_depth| {
        var current_depth: usize = 0;
        try output.writeByte(',');
        for (b_instruction_raster.items) |b| switch (b) {
            '\x80' => {
                current_depth += 1;
            },
            '\x81' => {
                current_depth -= 1;
            },
            ',' => {
                try output.writeByte(',');
            },
            else => |byte| {
                if (current_depth == crawl_depth) {
                    try output.writeByte(byte);
                }
            },
        };
        try output.writeAll("#,\n");
    }
    try output.writeByteNTimes(',', island_len + 2);
    try output.writeByte('\n');
}
