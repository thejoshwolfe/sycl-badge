const sin = @import("std").math.sin;
const cart = @import("cart-api");

const fromUtf8 = @import("./charset.zig").fromUtf8;

comptime {
    cart.export_start_code();

    assert(160 == cart.screen_width);
    assert(128 == cart.screen_height);
}

pub fn start() void {
    draw();
}

const Dot = enum { off, mid, high };

var last_controls: cart.Controls = @fromBackingInt(0xffff);
var super_state: union(enum) {
    main_menu,
    level_title: u8,
    level: u8,
    level_select: u8,
} = .main_menu;
var state: struct {
    pos: packed struct(u16) { x: u8, y: u8 } = .{ .x = 0, .y = 0 },
    dots: [10][8]Dot = @splat(@splat(.off)),
    zap_animation: ?struct { x: u8, y: u8, ttl: u64 } = null,
    background_animation_start: ?u64 = null,
} = .{};

pub fn update() void {
    defer draw();
    const controls = cart.controls.*;
    const new_controls: cart.Controls = @fromBackingInt(@backingInt(controls) & ~@backingInt(last_controls));
    defer {
        last_controls = controls;
    }

    switch (super_state) {
        .main_menu => {
            if (new_controls.a) {
                super_state = .{ .level_title = 1 };
            }
            if (new_controls.select) {
                super_state = .{ .level_select = 1 };
            }
        },
        .level_title => |level| {
            if (new_controls.start) {
                super_state = .main_menu;
            }
            if (new_controls.select) {
                super_state = .{ .level_select = level };
            }
            if (new_controls.a) {
                beginLevel(level);
            }
        },
        .level => |level| {
            updateLevel(level, new_controls);
        },
        .level_select => |level| {
            if (new_controls.a) {
                super_state = .{ .level_title = level };
            }
            if (new_controls.start) {
                super_state = .main_menu;
            }
            if (new_controls.up and level > 1) {
                super_state = .{ .level_select = level - 1 };
            }
            if (new_controls.down and level <= levels.len) {
                super_state = .{ .level_select = level + 1 };
            }
        },
    }
}

fn updateLevel(level: u8, new_controls: cart.Controls) void {
    // Meta navigation.
    if (new_controls.b) {
        // Reset.
        super_state = .{ .level_title = level };
        return;
    }
    if (new_controls.start) {
        super_state = .main_menu;
        return;
    }
    if (new_controls.select) {
        super_state = .{ .level_select = level };
        return;
    }
    if (state.background_animation_start) |t0| {
        // Winning.
        const now = cart.micros_since_boot();
        const t = (now - t0) / 10_000;
        if (t > 160 + 128 and new_controls.a) {
            clearNeopixels();
            if (level < 3) {
                super_state = .{ .level_title = level + 1 };
            } else {
                super_state = .main_menu;
            }
        } else return;
    }

    const old_pos = state.pos;
    if (new_controls.left and state.pos.x > 0) state.pos.x -= 1;
    if (new_controls.right and state.pos.x < 9) state.pos.x += 1;
    if (new_controls.up and state.pos.y > 0) state.pos.y -= 1;
    if (new_controls.down and state.pos.y < 7) state.pos.y += 1;
    if (old_pos != state.pos) {
        checkDots(level);
    }
}

fn beginLevel(level: u8) void {
    super_state = .{ .level = level };
    state = .{};
    checkDots(level);
}

const Level = struct {
    title: []const u8,
    title_line1: []const u8 = "",
    title_line2: []const u8 = "",
    phase1_fns: []const *const fn (*[10][8]Dot) void = &.{},
    phase2_fns: []const *const fn (*[10][8]Dot) void = &.{},
    check_win_fn: *const fn () u8,
};
const levels = [_]Level{
    .{
        .title = "Level 1",
        .title_line1 = fromUtf8("_¿÷. .¿÷_ ¯¿÷_"),
        .title_line2 = fromUtf8("_+.÷¯ 5¯÷¶"),
        .phase1_fns = &.{ @"_¿÷.", @".¿÷_", @"¯¿÷_" },
        .phase2_fns = &.{@"_+.÷¯"},
        .check_win_fn = @"5¯÷¶",
    },
    .{
        .title = "Level 2",
        .title_line1 = fromUtf8("¿+_÷+. ¯÷+¯"),
        .title_line2 = fromUtf8("».÷»¯ 80¯÷¶"),
        .phase1_fns = &.{ @"¿+_÷+.", @"¯÷+¯" },
        .phase2_fns = &.{@"».÷»¯"},
        .check_win_fn = @"80¯÷¶",
    },
    .{
        .title = "Level 3",
        .title_line1 = fromUtf8("_¿÷. .¿÷_ ¯¿÷_"),
        .title_line2 = fromUtf8("_+.÷¯ ¿+¯÷¶"),
        .phase1_fns = &.{ @"_¿÷.", @".¿÷_", @"¯¿÷_" },
        .phase2_fns = &.{@"_+.÷¯"},
        .check_win_fn = @"¿+¯÷¶",
    },
    .{
        .title = "Level 4",
        .title_line1 = fromUtf8("_¿÷. ¯¿÷_"),
        .title_line2 = fromUtf8("».÷»¯ 10.5¯÷¶"),
        .phase1_fns = &.{ @"_¿÷.", @"¯¿÷_" },
        .phase2_fns = &.{@"».÷»¯"},
        .check_win_fn = @"10.5¯÷¶",
    },
};

fn drawLevelTitle(level: u8) void {
    cart.rect(.{ .x = 0, .y = 0, .width = 160, .height = 128, .fill_color = black });
    clearNeopixels();
    drawTextCentered(levels[level - 1].title, 30, 2, white);
    drawTextCentered(levels[level - 1].title_line1, 55, 1, yellow);
    drawTextCentered(levels[level - 1].title_line2, 70, 1, yellow);
}

fn checkDots(level: u8) void {
    var output = state.dots;
    for (levels[level - 1].phase1_fns) |f| {
        f(&output);
    }
    state.dots = output;
    for (levels[level - 1].phase2_fns) |f| {
        f(&output);
    }
    state.dots = output;

    const pixel_count = levels[level - 1].check_win_fn();
    for (cart.neopixels, 0..) |*neopixel, i| {
        if (i < pixel_count) {
            neopixel.* = .{ .r = 0xff, .g = 0x0, .b = 0xff };
        } else {
            neopixel.* = .{ .r = 0x0, .g = 0x0, .b = 0x0 };
        }
    }
    if (pixel_count == 5) {
        state.background_animation_start = cart.micros_since_boot();
    }
}

fn @"_¿÷."(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (state.dots[x][y] == .off) {
        output[x][y] = .mid;
    }
}

fn @".¿÷_"(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (state.dots[x][y] == .mid) {
        output[x][y] = .off;
    }
}

fn @"¯¿÷_"(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (state.dots[x][y] == .high) {
        output[x][y] = .off;
    }
}

fn @"_+.÷¯"(output: *[10][8]Dot) void {
    for (1..9) |x| {
        for (1..7) |y| {
            if (state.dots[x][y] == .off and isCross(x, y, .mid)) {
                output[x][y] = .high;
                state.zap_animation = .{
                    .x = @intCast(x),
                    .y = @intCast(y),
                    .ttl = cart.micros_since_boot() + 200_000,
                };
            }
        }
    }
}

fn @"5¯÷¶"() u8 {
    var high_count: u8 = 0;
    for (0..10) |x| {
        for (0..8) |y| {
            if (state.dots[x][y] == .high) {
                high_count += 1;
            }
        }
    }
    return @min(5, high_count);
}

fn @"¿+_÷+."(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (isCross(x, y, .off)) {
        fillCross(output, x, y, .mid);
    }
}

fn @"».÷»¯"(output: *[10][8]Dot) void {
    for (0..8) |y| {
        if (isRow(y, .mid)) {
            for (0..10) |x| {
                output[x][y] = .high;
            }
        }
    }
}

fn @"¯÷+¯"(output: *[10][8]Dot) void {
    for (0..10) |x| {
        for (0..8) |y| {
            if (state.dots[x][y] == .high) {
                fillCross(output, x, y, .high);
            }
        }
    }
}

fn @"80¯÷¶"() u8 {
    var high_count: u8 = 0;
    for (0..10) |x| {
        for (0..8) |y| {
            if (state.dots[x][y] == .high) {
                high_count += 1;
            }
        }
    }
    return @min(5, high_count >> 4);
}

fn @"¿+¯÷¶"() u8 {
    if (isCross(state.pos.x, state.pos.y, .high)) {
        return 5;
    } else {
        return 0;
    }
}

fn @"10.5¯÷¶"() u8 {
    var mid_count: u8 = 0;
    var high_count: u8 = 0;
    for (0..10) |x| {
        for (0..8) |y| {
            if (state.dots[x][y] == .mid) {
                mid_count += 1;
            } else if (state.dots[x][y] == .high) {
                high_count += 1;
            }
        }
    }
    // No help.
    if (mid_count == 10 and high_count == 5) {
        return 5;
    } else {
        return 0;
    }
}

fn isCross(x: usize, y: usize, value: Dot) bool {
    if (x == 0 or x == 9 or y == 0 or y == 7) return false; // Too close to the edge.
    return (state.dots[x - 1][y] == value and
        state.dots[x + 1][y] == value and
        state.dots[x][y - 1] == value and
        state.dots[x][y + 1] == value);
}

fn isRow(y: usize, value: Dot) bool {
    for (0..10) |x| {
        if (state.dots[x][y] != value) return false;
    }
    return true;
}

fn fillCross(output: *[10][8]Dot, x: usize, y: usize, value: Dot) void {
    if (x > 0) output[x - 1][y] = value;
    if (x < 9) output[x + 1][y] = value;
    if (y > 0) output[x][y - 1] = value;
    if (y < 7) output[x][y + 1] = value;
}

fn clearNeopixels() void {
    for (cart.neopixels) |*neopixel| neopixel.* = .{ .r = 0x0, .g = 0x0, .b = 0x0 };
}

const black = rgb256(0, 0, 0);
const white = rgb256(0xff, 0xff, 0xff);
const yellow = rgb256(0xff, 0xff, 0x54);
const blue = rgb256(0x88, 0x88, 0xff);
const purple = rgb256(0xaa, 0x0, 0xaa);
/// Brain is easier typing in a familiar format. It's all an approximation anyway.
fn rgb256(r: u8, g: u8, b: u8) cart.DisplayColor {
    return .{
        .r = @intCast(r >> 3),
        .g = @intCast(g >> 2),
        .b = @intCast(b >> 3),
    };
}

fn draw() void {
    switch (super_state) {
        .main_menu => {
            drawControls();
            drawTextCentered("p is for", 10, 2, white);
            drawTextCentered("puzzle", 35, 3, white);
        },
        .level_title => |level| {
            drawLevelTitle(level);
        },
        .level => {
            drawLevel();
        },
        .level_select => |level| {
            drawLevelSelect(level);
        },
    }
}

fn drawControls() void {
    cart.rect(.{ .x = 0, .y = 0, .width = 160, .height = 128, .fill_color = black });

    cart.text(.{ .x = 20, .y = 69, .text_color = yellow, .str = fromUtf8("🅰÷continue") });
    cart.text(.{ .x = 20, .y = 79, .text_color = yellow, .str = fromUtf8("🅱÷reset") });
    cart.text(.{ .x = 20, .y = 89, .text_color = yellow, .str = fromUtf8("⊕÷controls") });
    cart.text(.{ .x = 20, .y = 99, .text_color = yellow, .str = fromUtf8("⊖÷level select") });
}

fn drawLevelSelect(level: u8) void {
    cart.rect(.{ .x = 0, .y = 0, .width = 160, .height = 128, .fill_color = black });
    for (levels, 0..) |level_defs, i| {
        cart.text(.{ .x = 30, .y = @intCast(20 + i * 10), .text_color = white, .str = level_defs.title });
    }

    cart.rect(.{ .x = 21, .y = (level - 1) * 10 + 21, .width = 8, .height = 8, .fill_color = blue });
}

fn drawTextCentered(str: []const u8, y: u8, scale: u3, color: cart.DisplayColor) void {
    const str_width = @as(u8, @intCast(str.len)) * cart.font_width * scale;
    const x = @as(u8, @intCast(160 / 2)) - @as(u8, @intCast(str_width / 2));
    cart.text(.{ .str = str, .x = x, .y = y, .scale = scale, .text_color = color });
}

const rainbow = [_]cart.DisplayColor{
    .rgb(0x002288),
    .rgb(0x2288aa),
    .rgb(0x88aaee),
    .rgb(0xaaeeaa),
    .rgb(0xeeaa88),
    .rgb(0xaa8822),
    .rgb(0x882200),
    .rgb(0x220022),
};

fn drawLevel() void {
    const now = cart.micros_since_boot();
    for (0..160) |x| {
        for (0..128) |y| {
            cart.framebuffer[x][y] = blk: {
                // Cursor
                if (state.pos.x * 16 + 3 <= x and x < state.pos.x * 16 + 13 and
                    state.pos.y * 16 + 3 <= y and y < state.pos.y * 16 + 13)
                    break :blk blue;
                // Zap animation
                if (state.zap_animation) |z| {
                    if (now < z.ttl and
                        (z.x * 16 + 7 <= x and x < z.x * 16 + 9 and z.y * 16 - 7 <= y and y < z.y * 16 + 23 or
                            z.y * 16 + 7 <= y and y < z.y * 16 + 9 and z.x * 16 - 7 <= x and x < z.x * 16 + 23))
                        break :blk purple;
                }
                // Grid border
                if ((x + 1) % 16 <= 1 or (y + 1) % 16 <= 1) break :blk yellow;
                // Center dots
                if ((x + 10) % 16 < 4 and (y + 10) % 16 < 4) break :blk switch (state.dots[x >> 4][y >> 4]) {
                    .off => black,
                    .mid => yellow,
                    .high => purple,
                };
                if (state.background_animation_start) |t0| {
                    const t = (now - t0) / 10_000;
                    if (t < x + y) break :blk black;
                    break :blk rainbow[@intCast(((t - (x + y)) >> 4) % rainbow.len)];
                }
                // Background
                break :blk black;
            };
        }
    }
}

fn assert(b: bool) void {
    if (!b) unreachable;
}
