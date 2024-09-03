const std = @import("std");
const Allocator = std.mem.Allocator;

pub extern fn logWasm(s: [*]const u8, len: usize) void;
pub extern fn showWords(s: [*]const u8, len: usize) void;

fn printErr(msg: []const u8, err: anyerror) void {
    print("Error: {any}\n Msg: {s}", .{ err, msg });
}

fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;

    const slice = std.fmt.bufPrint(&buf, fmt, args) catch |err| {
        printErr("Error printing", err);
        unreachable;
    };
    logWasm(slice.ptr, slice.len);
}

const alphabet = "abcdefghijklmnopqrstuvwxyz";

const word_obj = struct {
    word: []u8,
    bitField: [9]u26,
};

fn calcBitField(string: []u8) [9]u26 {
    var bitField = std.mem.zeroes([9]u26);

    for (string) |l| {
        const letter = [1]u8{
            l,
        };
        //std.debug.print("letter: {s}\n", .{letter});
        const index = std.mem.indexOf(u8, alphabet, &letter) orelse {
            print("Error parsing letter: {s} in word: {s}", .{ letter, string });
            unreachable;
        };
        var num: u26 = 1;
        num = std.math.shl(u26, num, 25 - index);
        //std.debug.print("index: {d:0>2} num: {b:0>26}\n", .{ index, num });
        for (0.., bitField) |i, bf| {
            //std.debug.print("   Bitfield: {d:0>2} num: {b:0>26}\n", .{ i, num & bf });
            if (num & bf == 0) {
                bitField[i] += num;
                break;
            }
        }
    }
    return bitField;
}

fn buildWord(string: []u8) word_obj {
    const word = std.heap.wasm_allocator.alloc(u8, string.len) catch |err| {
        printErr("Allocate space in buildWord", err);
        unreachable;
    };
    @memcpy(word, string);
    const bitField = calcBitField(string);
    const wordObj = word_obj{ .word = word, .bitField = bitField };
    return wordObj;
}

fn compareWordObjects(word1: [9]u26, letterList: [9]u26) bool {
    for (0.., word1) |i, wm| {
        if (wm == 0) {
            return true;
        }

        if ((wm & ~letterList[i] != 0)) {
            return false;
        }
    }
    return true;
}

fn sendWords() void {
    if (global.matches.items.len < 1) return;

    print("sub_matches: {} sub_matches_rm: {}", .{ global.sub_matches.items.len, global.sub_matches_rm.items.len });

    var words_al = std.ArrayList(u8).init(std.heap.wasm_allocator);
    defer words_al.deinit();

    for (global.sub_matches.items) |idx| {
        const word = global.word_data[idx];
        words_al.appendSlice(word.word) catch |err| {
            printErr("Error adding matching word to words_al ", err);
            unreachable;
        };
        words_al.append(0x0A) catch |err| {
            printErr("Error adding LF to words_al in getMatches ", err);
            unreachable;
        };
    }
    const buff = std.heap.wasm_allocator.alloc(u8, words_al.items.len) catch |err| {
        printErr("Creating buffer in manyWords", err);
        unreachable;
    };

    const slice = std.fmt.bufPrint(buff, "{s}", .{words_al.items}) catch |err| {
        printErr("bufPrinting slice in manyWords", err);
        unreachable;
    };

    //print("Sending string: {s}", .{slice});

    showWords(slice.ptr, slice.len);
}

pub export fn getMatches(len: usize) void {
    global.matches.clearAndFree();
    global.sub_matches.clearAndFree();
    global.sub_matches_rm.clearAndFree();

    const word = global_chunk[0..len];

    print("Checking word: {s}", .{word});

    const lettersObj = buildWord(word);

    for (0.., global.word_data) |i, wo| {
        //if (global.matches.items.len > 1000) {
        //    break;
        //}
        if (compareWordObjects(wo.bitField, lettersObj.bitField)) {
            global.matches.append(i) catch |err| {
                printErr("Error adding to matches", err);
            };
        }
    }

    global.sub_matches.appendSlice(global.matches.items) catch |err| {
        printErr("Error updating sub_matches", err);
        unreachable;
    };

    print("Matches: {}", .{global.matches.items.len});

    sendWords();
}

pub export fn updateMatches(len: usize) void {
    const word = global_chunk[0..len];

    print("Updating matches. Word: {s}", .{word});

    const lettersObj = buildWord(word);

    global.sub_matches.clearAndFree();

    for (global.matches.items) |idx| {
        const wo = global.word_data[idx];
        if (compareWordObjects(wo.bitField, lettersObj.bitField)) {
            global.matches.append(idx) catch |err| {
                printErr("Error adding to matches", err);
                unreachable;
            };

            global.sub_matches.append(idx) catch |err| {
                printErr("Error updating sub_matches", err);
                unreachable;
            };
        }
    }

    sendWords();
}

pub export fn removeMatches(len: usize) void {
    const word = global_chunk[0..len];

    //print("Removing matches. Word: {s}", .{word});

    const lettersObj = buildWord(word);

    var sub_matches_copy = std.ArrayList(usize).init(std.heap.wasm_allocator);
    defer sub_matches_copy.deinit();

    for (global.sub_matches.items) |idx| {
        const wo = global.word_data[idx];
        //print("Comparing word: {s}", .{wo.word});
        if (!compareWordObjects(wo.bitField, lettersObj.bitField)) {
            global.sub_matches_rm.append(idx) catch |err| {
                printErr("Error updating sub_matches_rm", err);
                unreachable;
            };
            //print("No Match", .{});
        } else {
            sub_matches_copy.append(idx) catch |err| {
                printErr("Error updating sub_matches in rmMatches", err);
                unreachable;
            };
        }
    }
    const copy = sub_matches_copy.toOwnedSlice() catch |err| {
        printErr("Error turning sub_matches_copy to owned slice", err);
        unreachable;
    };

    global.sub_matches.clearAndFree();

    print("sub_matches: {}  sub_matches_copy: {}", .{ global.sub_matches.items.len, sub_matches_copy.items.len });

    global.sub_matches.appendSlice(copy) catch |err| {
        printErr("Error replacing sub_matches in rmMatches", err);
        unreachable;
    };

    sendWords();
}

pub export fn addMatches(len: usize) void {
    const word = global_chunk[0..len];

    print("Adding matches. Word: {s}", .{word});

    const lettersObj = buildWord(word);

    var sub_matches_rm_copy = std.ArrayList(usize).init(std.heap.wasm_allocator);
    defer sub_matches_rm_copy.deinit();

    for (global.sub_matches_rm.items) |idx| {
        const wo = global.word_data[idx];
        if (compareWordObjects(wo.bitField, lettersObj.bitField)) {
            global.sub_matches.append(idx) catch |err| {
                printErr("Error updating sub_matches_rm", err);
                unreachable;
            };
        } else {
            sub_matches_rm_copy.append(idx) catch |err| {
                printErr("Error updating sub_matches_rm in addMatches", err);
                unreachable;
            };
        }
    }

    const copy = sub_matches_rm_copy.toOwnedSlice() catch |err| {
        printErr("Error turning sub_matches_rm_copy to owned slice", err);
        unreachable;
    };

    global.sub_matches_rm.clearAndFree();

    global.sub_matches_rm.appendSlice(copy) catch |err| {
        printErr("Error replacing sub_matches in addMatches", err);
        unreachable;
    };

    print("sub_matches_rm: {}", .{global.sub_matches_rm.items.len});

    sendWords();
}

pub export var global_chunk: [16384]u8 = undefined;
pub var last_word_completed = true;

pub export fn pushWordData(len: usize) void {
    var idx: usize = 0;
    while (true) {
        var word_al = std.ArrayList(u8).init(std.heap.wasm_allocator);
        defer word_al.deinit();

        // If the last word was not completed, add it to the start of the first word
        if (!last_word_completed) {
            const last_word_obj = global.word_data_al.pop();
            const last_word_str = last_word_obj.word;
            const last_word = std.heap.wasm_allocator.alloc(u8, last_word_str.len) catch |err| {
                printErr("Allocating space for last word", err);
                unreachable;
            };
            @memcpy(last_word, last_word_str);
            word_al.appendSlice(last_word) catch |err| {
                printErr("Appending lastword slice", err);
                unreachable;
            };

            last_word_completed = true;
        }

        while (global_chunk[idx] != 0x0A) {
            word_al.append(global_chunk[idx]) catch |err| {
                printErr("appending char to word_al", err);
                unreachable;
            };
            idx += 1;
            if (idx >= len) {
                last_word_completed = false;
                break;
            }
        }

        const word = std.heap.wasm_allocator.alloc(u8, word_al.items.len) catch |err| {
            printErr("Allocating space for pushed word", err);
            unreachable;
        };

        @memcpy(word, word_al.items);

        const wordObj = buildWord(word);

        global.word_data_al.append(wordObj) catch |err| {
            printErr("Appending wordObj to word_data", err);
            unreachable;
        };

        idx += 1;
        if (idx >= len) {
            break;
        }
    }
}

pub export fn finishedPushing() void {
    global.word_data = global.word_data_al.toOwnedSlice() catch |err| {
        printErr("Error converting word_data_al to owned slice", err);
        unreachable;
    };
    print("Pushed word data. Length: {}", .{global.word_data.len});
}

pub export fn getNWords() usize {
    return global.word_data.len;
}

const GlobalState = struct {
    word_data_al: std.ArrayList(word_obj) = std.ArrayList(word_obj).init(std.heap.wasm_allocator),
    word_data: []word_obj = undefined,
    matches: std.ArrayList(usize) = std.ArrayList(usize).init(std.heap.wasm_allocator),
    sub_matches: std.ArrayList(usize) = std.ArrayList(usize).init(std.heap.wasm_allocator),
    sub_matches_rm: std.ArrayList(usize) = std.ArrayList(usize).init(std.heap.wasm_allocator),
};

var global = GlobalState{};

//pub export fn get_word_data() []u8 {
//    return global.word_data.items;
//}

pub export fn testPrint() void {
    print("Hello, World!\n", .{});
}

pub export fn printWordData(index: usize) void {
    //var end_index = index + 1;
    //while (true) {
    //    if (global.word_data.items[end_index] == 0x0A) {
    //        break;
    //    }
    //    end_index += 1;
    //}
    print("Word Data: {s}\n", .{global.word_data[index].word});
}
