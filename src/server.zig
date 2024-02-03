const std = @import("std");
const http = std.http;
const uri = std.Uri.parse("http://192.168.2.25/report") catch unreachable;
const uri_off = std.Uri.parse("http://192.168.2.25/relay?state=0") catch unreachable;
var POWER_THRESHOLD: f32 = 120; // default value, maybe saved the last value received through HTTP API?
const Data = struct {
    power: f32,
    relay: bool,
};