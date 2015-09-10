module context;


import std.string;

import tags;
import utils;


class ParserException : Throwable {
	this(string msg, Context context) {
		super(msg);
		this.context = context;
	}

	Context context;
}


class Context {
	this(string sourceName, string source, size_t line = 1, size_t cursor = 0) {
		this.sourceName = sourceName;
		this.source = source;
		this.line = line;
		this.cursor = cursor;
	}

	auto advance(size_t offset) {
		line += source[cursor..cursor + offset].countLines;
		cursor += offset;
		return this;
	}

	auto remaining() {
		return source[cursor..$];
	}

	auto defining() {
		return defineCount > 0;
	}

	auto tagOpen(string tag, string content) {
		tagOpens ~= TagOpen(line, cursor, tag, content);
		if (tag == Tag.Define)
			++defineCount;
	}

	auto tagClose() {
		if (tagOpens.length == 0)
			throw new ParserException("unexpected '/' tag; no tag is open", this);
		auto tag = tagOpens[$-1];
		if (tag.tag == Tag.Define)
			--defineCount;
		tagOpens = tagOpens[0..$-1];
		return tag;
	}

	auto expectTagClosed() {
		if (tagOpens.length) {
			auto lastOpen = tagOpens[$-1];
			throw new ParserException("unexpected EOF; missing '/' tag for '" ~ lastOpen.tag ~ "'", new Context(sourceName, source, lastOpen.line, lastOpen.cursor));
		}
	}

	auto expectTagOpen(string tag, string related) {
		if (!tagOpens.length || tagOpens[$-1].tag != tag)
			throw new ParserException("unexpected '" ~ related ~ "' tag; no '" ~ tag ~ "' tag in open", this);
	}

	string sourceName;
	string source;
	size_t line;
	size_t cursor;
	size_t defineCount;

	struct TagOpen {
		size_t line;
		size_t cursor;
		string tag;
		string content;
	}

	private TagOpen[] tagOpens;
}
