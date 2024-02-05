const std = @import("std");
pub const http = std.http;
pub const uri_report = std.Uri.parse("http://192.168.2.25/report") catch unreachable;
pub const uri_off = std.Uri.parse("http://192.168.2.25/relay?state=0") catch unreachable;
pub var POWER_THRESHOLD: f32 = 120; // default value, maybe save the last value received through HTTP API?
pub var lastData: Data = Data{ .power = 0, .relay = false };

pub const Data = struct {
    power: f32,
    relay: bool,
};

pub fn runServer(server: *http.Server, alloc: std.mem.Allocator) !void {
    outer: while (true) {
        // Accept incoming connection.
        var response = try server.accept(.{
            .allocator = alloc,
        });
        defer response.deinit();

        // putting this in a while loop makes no sense if the server just has to deliver one information once per request
        //while (response.reset() != .closing) {
        // Handle errors during request processing.
        response.wait() catch |err| switch (err) {
            error.HttpHeadersInvalid => continue :outer,
            error.EndOfStream => continue,
            else => return err,
        };

        // Process the request.
        try handleRequest(&response, alloc);
        _ = response.reset();
        //}
    }
}

fn handleRequest(response: *http.Server.Response, alloc: std.mem.Allocator) !void {
    // Log the request details.
    // log.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

    // Read the request body.
    const body = try response.reader().readAllAlloc(alloc, 8192);
    defer alloc.free(body);

    // Set "connection" header to "keep-alive" if present in request headers.
    //if (response.request.headers.contains("connection")) {
    //    try response.headers.append("connection", "keep-alive");
    //}

    response.transfer_encoding = .chunked;
    try response.headers.append("content-type", "application/json");

    if (std.mem.startsWith(u8, response.request.target, "/power=")) { // change the power threshold for the myStrom plug
        const powerSetting: f32 = std.fmt.parseFloat(f32, response.request.target[7..]) catch 0;

        // left in as a general note on how to convert numbers to a string/slice
        //var oldPower: [3]u8 = undefined;
        //_ = std.fmt.bufPrint(&oldPower, "{d}", .{POWER_THRESHOLD}) catch @panic("error");

        //var newPower: [3]u8 = undefined;
        //_ = std.fmt.bufPrint(&newPower, "{d}", .{powerSetting}) catch @panic("error");

        // Is there a reason to not send it chunked? Maybe performance? Have to calculate content length if not chunked
        // Check if the request target contains "?chunked".
        //if (std.mem.indexOf(u8, response.request.target, "?chunked") != null) {
        //    response.transfer_encoding = .chunked;
        //} else {
        //    response.transfer_encoding = .{ .content_length = 10 };
        //}

        if (response.request.method != .HEAD) {
            try std.json.stringify(.{ .oldThreshold = POWER_THRESHOLD, .newThreshold = powerSetting }, .{}, response.writer());
            try response.finish();
        }
        POWER_THRESHOLD = powerSetting;
    } else if (std.mem.startsWith(u8, response.request.target, "/data")) { // request the last data containing power[W], relay state and the power threshold
        if (response.request.method != .HEAD) {
            //try std.json.stringify(.{ .@"Current threshold" = oldPower }, .{}, response.writer()); // spaces are allowed in json... but that looks odd
            try std.json.stringify(.{ .currentThreshold = POWER_THRESHOLD, .power = lastData.power, .relay = lastData.relay }, .{}, response.writer());
            try response.finish();
        }
    } else {
        // Set the response status to 404 (not found).
        response.status = .not_found;
    }
}
