const std = @import("std");
const serv = @import("myStromerRequestHandler.zig");

const Thread = std.Thread;
const log = std.log.scoped(.server);

var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 12 }){};
const allocator = gpa.allocator();

pub fn main() !void {
    var client: serv.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    // configuration API loop
    const handle = try Thread.spawn(.{}, threadWork, .{});
    handle.detach();

    // myStrom loop
    while (true) {
        std.time.sleep(30 * 1000 * 1000 * 1000);
        // if successful, move on, if error, continue (jump back to start)
        var req = client.fetch(allocator, .{.location = .{.uri = serv.uri_report}}) catch |err| { // uri_report
            log.err("Error while sending GET request: {s}\n", .{@errorName(err)});
            continue;
        };
        defer req.deinit();

        const body = req.body;

        if (validateJson(body.?)) {
            const res = try std.json.parseFromSliceLeaky(serv.Data, allocator, body.?, .{ .ignore_unknown_fields = true });
            serv.lastData = res;
            //read power value and relays state to decide if to turn off or not
            //std.debug.print("current power: {d:.2} | relay: {} | threshold: {d:.2}\n", .{ res.power, res.relay, serv.POWER_THRESHOLD });

            if ((res.power <= serv.POWER_THRESHOLD and res.power >= 20) and res.relay == true) {
                const req_off = try client.fetch(allocator, .{.location = .{.uri = serv.uri_off}});
                _ = req_off;
            }
        }
    }
}

fn threadWork() !void {
    // Initialize the server.
    const server_addr = "0.0.0.0";
    const server_port = 8000;

    var server = serv.http.Server.init(.{.reuse_address = true});
    defer server.deinit();

    log.info("Server is running at {s}:{d}", .{ server_addr, server_port });

    const address = std.net.Address.parseIp(server_addr, server_port) catch unreachable;
    try server.listen(address);

    while (true) {
        // Run the server.
        serv.runServer(&server, allocator) catch |err| {
            // Handle server errors.
            log.err("server error: {}\n", .{err});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
            std.os.exit(1);
        };
    }
}

// function wrapper for std.json.validate(), I only care if valid or not, not if some error happened
fn validateJson(string: []const u8) bool {
    const scanneroni = std.json.validate(allocator, string) catch false;
    if (scanneroni == false) {
        log.err("JSON string is NOT valid!\n", .{});
        return false;
    } else {
        return true;
    }
}
