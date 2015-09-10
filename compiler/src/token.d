module token;

import std.array;
import std.base64;
import std.datetime;
import std.digest.sha;
import std.random;
import std.socket;


private __gshared string token_;


void set(string token) {
	token_ = token;
}

auto get() {
	return token_;
}

void randomize() {
	auto now = Clock.currTime.stdTime;
	auto hostName = Socket.hostName;

	ubyte[] data;
	data.reserve(8 + hostName.length + 64 * 4);
	data ~= *cast(ubyte[8]*)(&now);
	data ~= cast(ubyte[])hostName;

	auto rng = Mt19937(unpredictableSeed());
	foreach(i; 0..64) {
		uint x = rng.front();
		data ~= *cast(ubyte[4]*)(&x);
	}

	alias Base64Token = Base64Impl!('-', '_', '\0');

	token_ = Base64Token.encode(sha1Of(data))[0..24];
}
