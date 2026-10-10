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

const Dot = enum { low, mid, high, super };

var last_controls: cart.Controls = @fromBackingInt(0xffff);
var super_state: union(enum) {
    main_menu,
    level_title: u8,
    level: u8,
    level_select: u8,
    end_credits,
} = .main_menu;
var state: struct {
    pos: packed struct(u16) { x: u8, y: u8 } = .{ .x = 0, .y = 0 },
    dots: [10][8]Dot = @splat(@splat(.low)),
    zap_animation: ?struct { x: u8, y: u8, ttl: u64 } = null,
    background_animation_start: ?u64 = null,
} = .{};
var completion_state: struct {
    levels_completed: [8]bool = @splat(false),
    level_1_secret: bool = false,
    level_3_secret: bool = false,
    level_5_secret: bool = false,
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
            if (new_controls.up) {
                super_state = .{ .level_select = switch (level) {
                    1 => 8,
                    9 => 1,
                    else => level - 1,
                } };
            }
            if (new_controls.down) {
                super_state = .{ .level_select = switch (level) {
                    8 => 1,
                    9 => 8,
                    else => level + 1,
                } };
            }
            if (level == 4 and new_controls.right) {
                super_state = .{ .level_select = 9 };
            }
            if (level == 9 and new_controls.left) {
                super_state = .{ .level_select = 4 };
            }
        },
        .end_credits => {
            // Jail.
        },
    }
}

fn updateLevel(level: u8, new_controls: cart.Controls) void {
    // Meta navigation.
    if (new_controls.b and levels[level - 1].b_press_fns.len == 0) {
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
            if (level < levels.len) {
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
        _ = checkDots(level, .movement);
    }
    if (new_controls.a) {
        _ = checkDots(level, .a_press);
    }
    if (levels[level - 1].b_press_fns.len > 0 and new_controls.b) {
        if (!checkDots(level, .b_press)) {
            // Reset.
            super_state = .{ .level_title = level };
            return;
        }
    }
}

fn beginLevel(level: u8) void {
    super_state = .{ .level = level };
    state = .{};
    _ = checkDots(level, .movement);
}

const Level = struct {
    title: []const u8,
    title_line1: []const u8 = "",
    title_line2: []const u8 = "",
    phase1_fns: []const *const fn (*[10][8]Dot) void = &.{},
    phase2_fns: []const *const fn (*[10][8]Dot) void = &.{},
    a_press_fns: []const *const fn (*[10][8]Dot) void = &.{},
    b_press_fns: []const *const fn () bool = &.{},
    check_win_fn: *const fn () u8,
    check_secret_fns: []const *const fn () void = &.{},
};
const levels = [_]Level{
    .{
        .title = "Level 1",
        .title_line1 = fromUtf8("_¿%. .¿%_ ¯¿%_"),
        .title_line2 = fromUtf8("_+.%¯ 5¯%¶"),
        .phase1_fns = &.{ @"_¿%.", @".¿%_", @"¯¿%_" },
        .phase2_fns = &.{@"_+.%¯"},
        .check_win_fn = @"5¯%¶",
        .check_secret_fns = &.{@"1£8¯"},
    },
    .{
        .title = "Level 2",
        .title_line1 = fromUtf8("¿+_%+. ¯%+¯"),
        .title_line2 = fromUtf8("».%»¯ 80¯%¶"),
        .phase1_fns = &.{ @"¿+_%+.", @"¯%+¯" },
        .phase2_fns = &.{@"».%»¯"},
        .check_win_fn = @"80¯%¶",
    },
    .{
        .title = "Level 3",
        .title_line1 = fromUtf8("_¿%. .¿%_ ¯¿%_"),
        .title_line2 = fromUtf8("_+.%¯ ¿+¯%¶"),
        .phase1_fns = &.{ @"_¿%.", @".¿%_", @"¯¿%_" },
        .phase2_fns = &.{@"_+.%¯"},
        .check_win_fn = @"¿+¯%¶",
        .check_secret_fns = &.{@"3£¿×¯"},
    },
    .{
        .title = "Level 4",
        .title_line1 = fromUtf8("_¿%. ¯¿%_"),
        .title_line2 = fromUtf8("».%»¯ 10.5¯%¶"),
        .phase1_fns = &.{ @"_¿%.", @"¯¿%_" },
        .phase2_fns = &.{@"».%»¯"},
        .check_win_fn = @"10.5¯%¶",
    },
    .{
        .title = "Level 5",
        .title_line1 = fromUtf8("_¿%. ¯¿%."),
        .title_line2 = fromUtf8("».¿🅰%+^ 5/%¶"),
        .phase1_fns = &.{ @"_¿%.", @"¯¿%." },
        .phase2_fns = &.{},
        .a_press_fns = &.{@"».¿🅰%+^"},
        .check_win_fn = @"5/%¶",
        .check_secret_fns = &.{@"5£¿×/"},
    },
    .{
        .title = "Level 6",
        .title_line1 = fromUtf8("¿+_%.+. ¯¿🅰%»¯"),
        .title_line2 = fromUtf8("_+.%¯ 40¯%¶"),
        .phase1_fns = &.{@"¿+_%.+."},
        .phase2_fns = &.{@"_+.%¯"},
        .a_press_fns = &.{@"¯¿🅰%»¯"},
        .check_win_fn = @"40¯%¶",
    },
    .{
        .title = "Level 7",
        .title_line1 = fromUtf8("_¿%. .¿%_"),
        .title_line2 = fromUtf8("¿+_×.🅰%×^ 5¯%¶"),
        .phase1_fns = &.{ @"_¿%.", @".¿%_" },
        .phase2_fns = &.{},
        .a_press_fns = &.{@"¿+_×.🅰%×^"},
        .check_win_fn = @"5¯%¶",
    },
    .{
        .title = "Level 8",
        .title_line1 = fromUtf8("_¿%. 54_».¿×.🅰%+^"),
        .title_line2 = fromUtf8("4¯%_ 3¯%^ ¯%_ 5/%¶"),
        .phase1_fns = &.{@"4¯%_ 3¯%^ ¯%_"},
        .phase2_fns = &.{@"_¿%."},
        .a_press_fns = &.{@"54_».¿×.🅰%+^"},
        .check_win_fn = @"5/%¶",
    },
    .{
        .title = "Level ??",
        .title_line1 = fromUtf8("1£8¯%×/ 3£¿×¯%»/"),
        .title_line2 = fromUtf8("5£¿×/%×/ ¿+/🅱%¶"),
        .phase1_fns = &.{@"1£8¯%×/ 3£¿×¯%»/ 5£¿×/%×/"},
        .phase2_fns = &.{},
        .b_press_fns = &.{@"¿+/🅱%¶"},
        .check_win_fn = @"¿+¯%¶",
    },
};

fn drawLevelTitle(level: u8) void {
    cart.rect(.{ .x = 0, .y = 0, .width = 160, .height = 128, .fill_color = black });
    clearNeopixels();
    drawTextCentered(levels[level - 1].title, 30, 2, white);
    drawTextCentered(levels[level - 1].title_line1, 55, 1, yellow);
    drawTextCentered(levels[level - 1].title_line2, 70, 1, yellow);
}

fn checkDots(level: u8, from_which_input: enum { movement, a_press, b_press }) bool {
    var output = state.dots;
    var b_press_handled = false;
    switch (from_which_input) {
        .movement => {
            for (levels[level - 1].phase1_fns) |f| {
                f(&output);
            }
            state.dots = output;
            for (levels[level - 1].phase2_fns) |f| {
                f(&output);
            }
            state.dots = output;
        },
        .a_press => {
            for (levels[level - 1].a_press_fns) |f| {
                f(&output);
            }
            state.dots = output;
        },
        .b_press => {
            for (levels[level - 1].b_press_fns) |f| {
                if (f()) b_press_handled = true;
            }
            state.dots = output;
        },
    }

    for (levels[level - 1].check_secret_fns) |f| {
        f();
    }

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
        completion_state.levels_completed[level - 1] = true;
    }

    return b_press_handled;
}

fn @"_¿%."(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (state.dots[x][y] == .low) {
        output[x][y] = .mid;
    }
}

fn @".¿%_"(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (state.dots[x][y] == .mid) {
        output[x][y] = .low;
    }
}

fn @"¯¿%_"(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (state.dots[x][y] == .high) {
        output[x][y] = .low;
    }
}

fn @"¯¿%."(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (state.dots[x][y] == .high) {
        output[x][y] = .mid;
    }
}

fn @"_+.%¯"(output: *[10][8]Dot) void {
    for (1..9) |x| {
        for (1..7) |y| {
            if (state.dots[x][y] == .low and isCross(x, y, .mid)) {
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

fn @"5¯%¶"() u8 {
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

fn @"¿+_%+."(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (isCross(x, y, .low)) {
        fillCross(output, x, y, .mid);
    }
}

fn @"».%»¯"(output: *[10][8]Dot) void {
    for (0..8) |y| {
        if (isRow(y, .mid)) {
            fillRow(output, y, .high);
        }
    }
}

fn @"¯%+¯"(output: *[10][8]Dot) void {
    for (0..10) |x| {
        for (0..8) |y| {
            if (state.dots[x][y] == .high) {
                fillCross(output, x, y, .high);
            }
        }
    }
}

fn @"80¯%¶"() u8 {
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

fn @"¿+¯%¶"() u8 {
    if (isCross(state.pos.x, state.pos.y, .high)) {
        return 5;
    } else {
        return 0;
    }
}

fn @"10.5¯%¶"() u8 {
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

fn @"¿+_%.+."(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (isCross(x, y, .low)) {
        output[x][y] = .mid;
        fillCross(output, x, y, .mid);
    }
}

fn @"¯¿🅰%»¯"(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (state.dots[x][y] != .high) return;
    fillRow(output, y, .high);
}

fn @"40¯%¶"() u8 {
    var high_count: u8 = 0;
    for (0..10) |x| {
        for (0..8) |y| {
            if (state.dots[x][y] == .high) {
                high_count += 1;
            }
        }
    }
    return @min(5, @divCeil(high_count, 8));
}

fn @"».¿🅰%+^"(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (!isRow(y, .mid)) return;
    incrementCross(output, x, y);
}

fn @"5/%¶"() u8 {
    var super_count: u8 = 0;
    for (0..10) |x| {
        for (0..8) |y| {
            if (state.dots[x][y] == .super) {
                super_count += 1;
            }
        }
    }
    return @min(5, super_count);
}

fn @"¿+_×.🅰%×^"(output: *[10][8]Dot) void {
    const x = state.pos.x;
    const y = state.pos.y;
    if (!isCross(x, y, .low)) return;
    if (!isDiagonal(x, y, .mid)) return;
    incrementDiagonal(output, x, y);
}

fn @"4¯%_ 3¯%^ ¯%_"(output: *[10][8]Dot) void {
    var high_count: u8 = 0;
    for (0..10) |x| {
        for (0..8) |y| {
            if (state.dots[x][y] == .high) {
                high_count += 1;
            }
        }
    }

    if (high_count == 3) {
        for (0..10) |x| {
            for (0..8) |y| {
                if (state.dots[x][y] == .high) {
                    output[x][y] = .super;
                }
            }
        }
    } else {
        for (0..10) |x| {
            for (0..8) |y| {
                if (state.dots[x][y] == .high) {
                    output[x][y] = .low;
                }
            }
        }
    }
}

fn @"54_».¿×.🅰%+^"(output: *[10][8]Dot) void {
    var low_count: u8 = 0;
    for (0..10) |x| {
        for (0..8) |y| {
            if (state.dots[x][y] == .low) {
                low_count += 1;
            }
        }
    }
    if (low_count < 54) return;
    const x = state.pos.x;
    const y = state.pos.y;
    if (!isRow(y, .mid)) return;
    if (!isDiagonal(x, y, .mid)) return;
    incrementCross(output, x, y);
}

fn @"1£8¯"() void {
    var high_count: u8 = 0;
    for (0..10) |x| {
        for (0..8) |y| {
            if (state.dots[x][y] == .high) {
                high_count += 1;
            }
        }
    }
    if (high_count >= 8) {
        completion_state.level_1_secret = true;
    }
}

fn @"3£¿×¯"() void {
    if (isDiagonal(state.pos.x, state.pos.y, .high)) {
        completion_state.level_3_secret = true;
    }
}

fn @"5£¿×/"() void {
    if (isDiagonal(state.pos.x, state.pos.y, .super)) {
        completion_state.level_5_secret = true;
    }
}

fn @"1£8¯%×/ 3£¿×¯%»/ 5£¿×/%×/"(output: *[10][8]Dot) void {
    if (completion_state.level_1_secret) fillDiagonal(output, 0, 0, .super);
    if (completion_state.level_3_secret) fillRow(output, 2, .super);
    if (completion_state.level_5_secret) fillDiagonal(output, 0, 4, .super);
}

fn @"¿+/🅱%¶"() bool {
    if (isCross(state.pos.x, state.pos.y, .super)) {
        super_state = .end_credits;
        return true;
    }
    return false;
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

fn fillRow(output: *[10][8]Dot, y: usize, value: Dot) void {
    for (0..10) |x| {
        output[x][y] = value;
    }
}

fn fillCross(output: *[10][8]Dot, x: usize, y: usize, value: Dot) void {
    if (x > 0) output[x - 1][y] = value;
    if (x < 9) output[x + 1][y] = value;
    if (y > 0) output[x][y - 1] = value;
    if (y < 7) output[x][y + 1] = value;
}

fn incrementCross(output: *[10][8]Dot, x: usize, y: usize) void {
    if (x > 0) output[x - 1][y] = incrementValue(state.dots[x - 1][y]);
    if (x < 9) output[x + 1][y] = incrementValue(state.dots[x + 1][y]);
    if (y > 0) output[x][y - 1] = incrementValue(state.dots[x][y - 1]);
    if (y < 7) output[x][y + 1] = incrementValue(state.dots[x][y + 1]);
}

fn isDiagonal(x: usize, y: usize, value: Dot) bool {
    if (x == 0 or x == 9 or y == 0 or y == 7) return false; // Too close to the edge.
    return (state.dots[x - 1][y - 1] == value and
        state.dots[x + 1][y - 1] == value and
        state.dots[x + 1][y + 1] == value and
        state.dots[x - 1][y + 1] == value);
}

fn fillDiagonal(output: *[10][8]Dot, x: usize, y: usize, value: Dot) void {
    if (x > 0 and y > 0) output[x - 1][y - 1] = value;
    if (x < 9 and y > 0) output[x + 1][y - 1] = value;
    if (x < 9 and y < 7) output[x + 1][y + 1] = value;
    if (x > 0 and y < 7) output[x - 1][y + 1] = value;
}

fn incrementDiagonal(output: *[10][8]Dot, x: usize, y: usize) void {
    if (x > 0 and y > 0) output[x - 1][y - 1] = incrementValue(state.dots[x - 1][y - 1]);
    if (x < 9 and y > 0) output[x + 1][y - 1] = incrementValue(state.dots[x + 1][y - 1]);
    if (x < 9 and y < 7) output[x + 1][y + 1] = incrementValue(state.dots[x + 1][y + 1]);
    if (x > 0 and y < 7) output[x - 1][y + 1] = incrementValue(state.dots[x - 1][y + 1]);
}

fn incrementValue(value: Dot) Dot {
    return switch (value) {
        .low => .mid,
        .mid => .high,
        .high => .super,
        .super => .low,
    };
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
            clearNeopixels();
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
        .end_credits => {
            drawEndCredits();
        },
    }
}

fn drawControls() void {
    cart.rect(.{ .x = 0, .y = 0, .width = 160, .height = 128, .fill_color = black });

    cart.text(.{ .x = 20, .y = 69, .text_color = yellow, .str = fromUtf8("🅰%continue") });
    cart.text(.{ .x = 20, .y = 79, .text_color = yellow, .str = fromUtf8("🅱%reset") });
    cart.text(.{ .x = 20, .y = 89, .text_color = yellow, .str = fromUtf8("⊕%controls") });
    cart.text(.{ .x = 20, .y = 99, .text_color = yellow, .str = fromUtf8("⊖%level select") });
}

fn drawEndCredits() void {
    const t: u8 = @intCast((cart.micros_since_boot() / 100_000) % rainbow.len);
    for (cart.neopixels, 0..) |*neopixel, i| {
        const color = rainbow[((5 - i) + t) % rainbow.len];
        neopixel.* = .{
            .r = color.r << 2,
            .g = color.g << 2,
            .b = color.b << 2,
        };
    }

    cart.rect(.{ .x = 0, .y = 0, .width = 160, .height = 128, .fill_color = black });
    drawTextCentered("The End", 10, 2, white);
    drawTextCentered("thanks for playing", 40, 1, yellow);
    drawTextCentered("my puzzle game!", 50, 1, yellow);
    drawTextCentered("  - Josh Wolfe", 70, 1, yellow);
    drawTextCentered("     SYLC 2026", 80, 1, yellow);
}

fn drawLevelSelect(level: u8) void {
    cart.rect(.{ .x = 0, .y = 0, .width = 160, .height = 128, .fill_color = black });
    // Titles
    for (levels[0..8], 0..) |level_defs, i| {
        cart.text(.{ .x = 20, .y = @intCast(20 + i * 10), .text_color = white, .str = level_defs.title });
    }
    if (level == 9) {
        cart.text(.{ .x = 90, .y = 20 + 3 * 10, .text_color = white, .str = levels[9 - 1].title });
    }

    // Completion dots
    for (0..8) |i| {
        if (completion_state.levels_completed[i]) {
            cart.rect(.{ .x = 13, .y = @as(i32, @intCast(i)) * 10 + 22, .width = 4, .height = 4, .fill_color = purple });
        }
    }
    if (completion_state.level_1_secret) {
        cart.rect(.{ .x = 12, .y = 0 * 10 + 21, .width = 5, .height = 5, .fill_color = white });
    }
    if (completion_state.level_3_secret) {
        cart.rect(.{ .x = 12, .y = 2 * 10 + 21, .width = 5, .height = 5, .fill_color = white });
    }
    if (completion_state.level_5_secret) {
        cart.rect(.{ .x = 12, .y = 4 * 10 + 21, .width = 5, .height = 5, .fill_color = white });
    }

    // Cursor
    if (level < 9) {
        cart.rect(.{ .x = 11, .y = (level - 1) * 10 + 20, .width = 8, .height = 8, .fill_color = blue });
    } else {
        cart.rect(.{ .x = 81, .y = 3 * 10 + 20, .width = 8, .height = 8, .fill_color = blue });
    }
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
                    .low => black,
                    .mid => yellow,
                    .high => purple,
                    .super => white,
                };
                // Super dots are slightly larger.
                if ((x + 11) % 16 < 6 and (y + 11) % 16 < 6 and state.dots[x >> 4][y >> 4] == .super) break :blk white;
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
