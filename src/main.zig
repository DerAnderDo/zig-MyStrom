// TODO: restrict turn on before 21:00

const std = @import("std");
const uri = std.Uri.parse("http://192.168.2.25/report") catch unreachable;
const uri_off = std.Uri.parse("http://192.168.2.25/relay?state=0") catch unreachable;
const POWER_THRESHOLD: u8 = 140;

var gpa_client = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 12 }){};
const calloc = gpa_client.allocator();

const Data = struct {
        power: f32,
        Ws: f32,
        relay: bool,
        temperature: f32,
};

pub fn main() !void {
    var client: std.http.Client = .{ .allocator = calloc };
    defer client.deinit();

    while(true) {
        std.time.sleep(30 * 1000 * 1000 * 1000);

        // if successful, move on, if error, continue (jump back to start)
        var req = client.request(.GET, uri, .{ .allocator = calloc }, .{}) catch |err| {
            std.debug.print("Error while sending GET request: {s}\n", .{@errorName(err)});
            continue;
        };

        defer req.deinit();
        try req.start();
        try req.wait();

        const body = req.reader().readAllAlloc(calloc, 8192) catch unreachable;
        defer calloc.free(body);

        //validate json string
        if ( validateJson(body) ) {

            //parse json string
            const res = try std.json.parseFromSliceLeaky(Data, calloc, body, .{});

            //read power value and relays state to decide if to turn off or not
            std.debug.print("current power: {d:.2} | relay: {}\n", .{res.power, res.relay});

            if ( (res.power <= POWER_THRESHOLD and res.power >= 20) and res.relay == true ) {
                var req_off = try client.request(.GET, uri_off, .{ .allocator = calloc }, .{});
                defer req_off.deinit();
                try req_off.start();
                try req_off.wait();
            }
        }
    }
}

fn validateJson(string: []const u8) bool { // function wrapper
    var scanneroni = std.json.validate(calloc, string) catch false;
    if (scanneroni == false){
        std.debug.print("JSON string is NOT valid!\n", .{});
        return false;
    } else { return true; }
}