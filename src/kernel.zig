const bss = @extern([*]u8, .{ .name = "__bss" });
const bss_end = @extern([*]u8, .{ .name = "__bss_end" });
const stack_top = @extern([*]u8, .{ .name = "__stack_top" });

const SbiRet = struct {
    @"error": isize,
    value: isize,
};

fn sbi_call(
    arg0: isize,
    arg1: isize,
    arg2: isize,
    arg3: isize,
    arg4: isize,
    arg5: isize,
    fid: isize,
    eid: isize,
) SbiRet {
    var err: isize = undefined;
    var value: isize = undefined;

    asm volatile ("ecall"
        : [err] "={a0}" (err),
          [value] "={a1}" (value),
        : [arg0] "{a0}" (arg0),
          [arg1] "{a1}" (arg1),
          [arg2] "{a2}" (arg2),
          [arg3] "{a3}" (arg3),
          [arg4] "{a4}" (arg4),
          [arg5] "{a5}" (arg5),
          [fid] "{a6}" (fid),
          [eid] "{a7}" (eid),
        : .{ .memory = true }
    );

    return .{ .@"error" = err, .value = value };
}

export fn kernel_main() noreturn {
    const bss_len = bss_end - bss;
    @memset(bss[0..bss_len], 0);

    print("\n\nHello {}!\n", .{"World"});
    print("1 + 2 = {}, {x}\n", .{ 1 + 2, 0x1234abcd });

    while (true) {
        asm volatile ("wfi");
    }
}

export fn boot() linksection(".text.boot") callconv(.naked)
    void {
        _ = asm volatile (
            \\mv sp, %[stack_top]
            \\j kernel_main
            :
            : [stack_top] "r" (stack_top),
        );
}

fn putchar(ch: u8) void {
    _ = sbi_call(ch, 0, 0, 0, 0, 0, 0, 1);
}


fn print(comptime fmt: []const u8, args: anytype) void {
    comptime var pos: usize = 0;
    comptime var arg_index: usize = 0;

    inline while (pos < fmt.len) {
        if (comptime fmt[pos] == '{') {
            comptime var base: u8 = 10;

            if (comptime pos + 1 < fmt.len and fmt[pos + 1] == '}') {
                pos += 2;
            } else if (comptime pos + 2 < fmt.len and
                fmt[pos + 1] == 'x' and fmt[pos + 2] == '}')
            {
                base = 16;
                pos += 3;
            } else {
                @compileError("expected {} or {x}");
            }

            if (comptime arg_index >= args.len) {
                @compileError("too few arguments");
            }

            printValue(args[arg_index], base);
            arg_index += 1;
        } else {
            if (comptime fmt[pos] == '}') {
                @compileError("unexpected }");
            }

            putchar(fmt[pos]);
            pos += 1;
        }
    }

    if (comptime arg_index != args.len) {
        @compileError("too many arguments");
    }
}

fn printValue(value: anytype, comptime base: u8) void {
    switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => printInt(value, base),
        .pointer => {
            if (comptime base != 10) {
                @compileError("{x} requires an integer");
            }

            const bytes: []const u8 = value;
            for (bytes) |ch| {
                putchar(ch);
            }
        },
        else => @compileError("unsupported argument type"),
    }
}

fn printInt(value: anytype, comptime base: u8) void {
    const digits = "0123456789abcdef";

    var buffer: [20]u8 = undefined;
    var start: usize = buffer.len;

    var magnitude: u64 = @intCast(@abs(value));

    while (true) {
        start -= 1;
        buffer[start] = digits[@intCast(magnitude % base)];
        magnitude /= base;

        if (magnitude == 0) break;
    }

    if (value < 0) {
        putchar('-');
    }

    for (buffer[start..]) |ch| {
        putchar(ch);
    }
}
