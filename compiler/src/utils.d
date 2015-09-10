module utils;


import std.array;
import std.string;
import std.utf;

public import jax.filters;


string quoted(string x, char q = '\"') {
	return concat(q, x, q);
}


string unquoted(string x, char q = '\0') {
	if (!q) {
		if (((x[0] == '\'') || (x[0] == '\"')) && (x[0] == x[$-1]))
			return x[1..$-1];
	} else {
		if ((x[0] == q) && (x[$-1] == q))
			return x[1..$-1];
	}
	return x;
}


bool balancedQuotes(Range)(Range range) {
	char open = '\0';
	char last = '\0';
	foreach(ch; range) {
		if (last != '\\') {
			switch(ch) {
				case '"':
					open = (open == '"') ? '\0' : '"';
					break;
				case '\'':
					open = (open == '\'') ? '\0' : '\'';
					break;
				case '`':
					open = (open == '`') ? '\0' : '`';
					break;
				default:
					break;
			}
		}
		last = ch;
	}
	return open == '\0';
}


bool balanced(Range, Char)(Range range, Char open, Char close) {
	int opens = 0;
	foreach(c; range) {
		if (c == open) {
			++opens;
		}
		if (c == close) {
			--opens;
		}
		if (opens < 0)
			return false;
	}
	return opens == 0;
}


size_t countLines(string x) {
	size_t count;
	foreach(i; 0..x.length)
		count += (x.ptr[i] == '\n');

	return count;
}


string unescapeJS(string x) {
	auto app = appender!string;
	app.reserve(x.length);

	bool seq;
	foreach (ch; x.byDchar) {
		switch (ch) {
			case '\\':
				if (seq) {
					app.put('\\');
					seq = false;
				} else {
					seq = true;
				}
				break;
			case '\'':
				app.put('\'');
				seq = false;
				break;
			case '\"':
				app.put('\"');
				seq = false;
				break;
			case 'r':
				app.put(seq ? '\r' : 'r');
				seq = false;
				break;
			case 'n':
				app.put(seq ? '\n' : 'n');
				seq = false;
				break;
			default:
				app.put(ch);
				break;
		}
	}
	return app.data;
}


string stripUTFbyteOrderMarker(string x) {
    if (x.length >= 3 && (x[0] == 0xef) && (x[1] == 0xbb) && (x[2] == 0xbf))
        return x[3..$];
    return x;
}
