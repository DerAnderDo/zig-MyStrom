// TODO: restrict turn on before 21:00

const std = @import("std");
const http = std.http;
// myStrom part
const uri = std.Uri.parse("http://192.168.2.25/report") catch unreachable;
const uri_off = std.Uri.parse("http://192.168.2.25/relay?state=0") catch unreachable;
var POWER_THRESHOLD: f32 = 140; // default value, maybe saved the last value received through HTTP API?
// configuration API part
const Thread = std.Thread;
const log = std.log.scoped(.server);
const server_addr = "0.0.0.0";
const server_port = 8000;

var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 12 }){};
const allocator = gpa.allocator();

const Data = struct {
    power: f32,
    relay: bool,
};

// Run the server and handle incoming requests.
fn runServer(server: *http.Server, alloc: std.mem.Allocator) !void {
    outer: while (true) {
        // Accept incoming connection.
        var response = try server.accept(.{
            .allocator = alloc,
        });
        defer response.deinit();

        while (response.reset() != .closing) {
            // Handle errors during request processing.
            response.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :outer,
                error.EndOfStream => continue,
                else => return err,
            };

            // Process the request.
            try handleRequest(&response, alloc);
        }
    }
}

// Handle an individual request.
fn handleRequest(response: *http.Server.Response, alloc: std.mem.Allocator) !void {
    // Log the request details.
    log.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

    // Read the request body.
    const body = try response.reader().readAllAlloc(alloc, 8192);
    defer alloc.free(body);

    // Set "connection" header to "keep-alive" if present in request headers.
    if (response.request.headers.contains("connection")) {
        try response.headers.append("connection", "keep-alive");
    }

    // Check if the request target starts with "/get".
    if (std.mem.startsWith(u8, response.request.target, "/power=")) {

        var powerSetting: f32 = try std.fmt.parseFloat(f32, response.request.target[7..]);

        var oldPower: [4]u8 = undefined;
        _ = std.fmt.bufPrintZ(&oldPower, "{d}", .{POWER_THRESHOLD}) catch @panic("error");

        var newPower: [4]u8 = undefined;
        _ = std.fmt.bufPrintZ(&newPower, "{d}", .{powerSetting}) catch @panic("error");

        POWER_THRESHOLD = powerSetting;

        // unused code
        // Check if the request target contains "?chunked".
        //if (std.mem.indexOf(u8, response.request.target, "?chunked") != null) {
        //    response.transfer_encoding = .chunked;
        //} else {
        //    response.transfer_encoding = .{ .content_length = 10 };
        //}
        response.transfer_encoding = .chunked;
        // Set "content-type" header to "text/plain".
        try response.headers.append("content-type", "text/plain");

        // Write the response body
        // Reply with previous power threshold and if setting the new one was succesful
        try response.do();
        if (response.request.method != .HEAD) {
            try response.writeAll("Old power threshold: ");
            try response.writeAll(&oldPower); try response.writeAll("\n");
            try response.writeAll("New power threshold: ");
            try response.writeAll(&newPower); try response.writeAll("\n");
            try response.finish();
        }
    } else if (std.mem.startsWith(u8, response.request.target, "/settings")) {
        var oldPower: [4]u8 = undefined;
        _ = std.fmt.bufPrintZ(&oldPower, "{d}", .{POWER_THRESHOLD}) catch @panic("error");
        response.transfer_encoding = .chunked;
        try response.headers.append("content-type", "text/plain");
        try response.do();
        if (response.request.method != .HEAD) {
            try response.writeAll("Current power threshold: ");
            try response.writeAll(&oldPower); try response.writeAll("\n");
            try response.finish();
        }
    } else {
        // Set the response status to 404 (not found).
        response.status = .not_found;
        try response.do();
    }
}

pub fn main() !void {
    var client: http.Client = .{ .allocator = allocator };
    defer client.deinit();

    // configuration API thread
    const handle = try Thread.spawn(.{}, threadWork, .{});
    handle.detach();

    // myStrom API loop
    while (true) {
        std.time.sleep(30 * 1000 * 1000 * 1000);

        // if successful, move on, if error, continue (jump back to start)
        var req = client.request(.GET, uri, .{ .allocator = allocator }, .{}) catch |err| {
            std.debug.print("Error while sending GET request: {s}\n", .{@errorName(err)});
            continue;
        };

        defer req.deinit();
        try req.start(.{});
        try req.wait();

        const body = req.reader().readAllAlloc(allocator, 8192) catch unreachable;
        defer allocator.free(body);

        //validate json string
        if (validateJson(body)) {

            //parse json string
            const res = try std.json.parseFromSliceLeaky(Data, allocator, body, .{ .ignore_unknown_fields = true });

            //read power value and relays state to decide if to turn off or not
            std.debug.print("current power: {d:.2} | relay: {} | setting: {}\n", .{ res.power, res.relay, POWER_THRESHOLD });

            if ((res.power <= POWER_THRESHOLD and res.power >= 20) and res.relay == true) {
                var req_off = try client.request(.GET, uri_off, .{ .allocator = allocator }, .{});
                defer req_off.deinit();
                try req_off.start(.{});
                try req_off.wait();
            }
        }
    }
}

fn threadWork() !void
{
    // Initialize the server.
    var server = http.Server.init(allocator, .{ .reuse_address = true });
    defer server.deinit();

    // Log the server address and port.
    log.info("Server is running at {s}:{d}", .{ server_addr, server_port });

    // Parse the server address.
    const address = std.net.Address.parseIp(server_addr, server_port) catch unreachable;
    try server.listen(address);

    while (true)
    {
        // Run the server.
        runServer(&server, allocator) catch |err| {
        // Handle server errors.
        log.err("server error: {}\n", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        std.os.exit(1);
        };
    }
}

fn validateJson(string: []const u8) bool { // function wrapper
    var scanneroni = std.json.validate(allocator, string) catch false;
    if (scanneroni == false) {
        std.debug.print("JSON string is NOT valid!\n", .{});
        return false;
    } else {
        return true;
    }
}
