const std = @import("std");

export fn string_isnumber(str: [*:0]const u8) bool {
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {
        if (!std.ascii.isDigit(str[i])) {
            return false;
        }
    }
    return i > 0;
}

test "string_isnumber" {
    try std.testing.expect(string_isnumber("1234"));
    try std.testing.expect(!string_isnumber("1234a"));
    try std.testing.expect(!string_isnumber("a1234"));
    try std.testing.expect(!string_isnumber("1234a5678"));
    try std.testing.expect(!string_isnumber("a1234a5678"));
    try std.testing.expect(!string_isnumber("a"));
    try std.testing.expect(!string_isnumber(""));
}
