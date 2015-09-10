module parser;


import std.algorithm;
import std.array;
import std.conv;
import std.stdio;
import std.string;

import compressor;
import context;
import definer;
import lexer;
import tags;
import token;
import utils;


struct Parser {
	struct Options {
		CompressOptions compression = CompressOptions.defaults;
		bool lines;
		string[] search;
		string[]* deps;
	}

	this(Options options) {
		this.options = options;
		this.settings = [ "defaultFilters": [ Setting(0, "defaults", "html") ], ];
	}

	static string compile(string fileName, Options options) {
		auto source = Definer.process(fileName, Definer.Options(options.lines, options.search, options.deps));
		//writeln(source);
		auto parser = Parser(options);

		source = parser.compileString(fileName, source)
			.replace("`);write(`", "")  // collapse consecutive writes
			.replace("\r\n", "\n");     // convert windows to unix line endings to save some bytes

		return source;
	}

private:
	string compileString(string sourceName, string source) {
		try {
			return parseSource(sourceName, source);
		} catch(ParserException parserError) {
			std.stdio.stderr.writeln(parserError.context.sourceName, '(', parserError.context.line, "): ", parserError.msg);
			return null;
		}
	}


	string parseSource(string sourceName, string source) {
		auto context = new Context(sourceName, source);

		Appender!string result;
		result.reserve(64 * 1024);

		const size_t end = source.length - min(Tag.OpenTag.length, Tag.CloseTag.length);
		while (context.cursor < end) {
			auto remaining = context.remaining();
			auto indexOpen = remaining.indexOf(Tag.OpenTag);
			if (indexOpen == -1)
				break;

			if (!context.defining)
				result.put(escaper(remaining[0..indexOpen], context));
			context.advance(indexOpen);

			const size_t contentStart = indexOpen + Tag.OpenTag.length;
			auto indexClose = remaining.indexOf(Tag.CloseTag, contentStart);
			while (indexClose != -1) {
				if (balancedQuotes(remaining[contentStart..indexClose]))
					break;

				indexClose = remaining.indexOf(Tag.CloseTag, indexClose + Tag.CloseTag.length);
			}

			if (indexClose == -1)
				throw new ParserException(concat("missing '", cast(string)Tag.CloseTag, "' to close tag '", cast(string)Tag.OpenTag, "'"), context);

			context.advance(Tag.OpenTag.length);
			indexClose -= contentStart;

			auto replaced = replacer(source[context.cursor..context.cursor + indexClose], context);
			if (!context.defining)
				result.put(replaced);
			context.advance(indexClose + Tag.CloseTag.length);
		}
		context.expectTagClosed();

		result.put((context.cursor > 0) ? escaper(context.remaining(), context) : escaper(source, context));

		context.advance(context.remaining.length);

		foreach(name, values; settings) {
			if (values.length > 1)
				throw new ParserException(("missing pop for '", name, "' - stack is not empty"), context);
		}

		return result.data();
	}


	auto iterate(string content, Context context) {
		context.tagOpen(content[0..1], content[1..$]);
		content = content[1..$].strip();
		return concat("{foreach(", content, "){");
	}


	auto close(string content, Context context) {
		auto tag = context.tagClose();
		return Tag.CloseTag;
	}


	auto conditional(string content, Context context) {
		context.tagOpen(content[0..1], content[1..$]);
		content = content[1..$].strip();
		return concat("{if(", content, "){");
	}


	auto orelse(string content, Context context) {
		context.expectTagOpen("?", ":");
		content = content[1..$];
		if (content.length)
			return concat("}else if(", content, "){");
		return "}else{";
	}


	auto eval(string content, Context context) {
		return content[1..$];
	}

	auto filter(string content, string[] filters, Context context) {
		foreach(i, filter; filters) {
			filter = filter.strip;
			// note: if you add a filter here, remember to update include() in definer.d if applicable
			switch (filter) {
				case "capitalize":
					content ~= ".capitalize";
					break;
				case "lower":
					content ~= ".toLower";
					break;
				case "upper":
					content ~= ".toUpper";
					break;
				case "none":
					break;
				case "html":
					content ~= ".escapeHTML";
					break;
				case "format_html":
					content ~= ".formatHTML!(FormatHTMLOptions.Escape)";
					break;
				case "format_html_links":
					content ~= ".formatHTML!(FormatHTMLOptions.Escape | FormatHTMLOptions.CreateLinks)";
					break;
				case "js":
					content ~= ".escapeJS";
					break;
				case "url":
					content ~= ".encodeURI";
					break;
				case "token_url":
					content ~= format(`.appendURIParam("v", "%s")`, token.get);
					break;
				default:
					throw new ParserException(concat("invalid filter '", filter, "'"), context);
			}
		}
		return content;
	}

	auto translate(string content, Context context) {
		content	= content[1..$].strip;

		auto filters = getSetting("defaultFilters").split(',');
		auto pipe = content.lastIndexOf("|");
		if (pipe != -1) {
			filters = content[pipe + 1..$].split(',');
		} else {
			pipe = content.length;
		}

		auto indexOpen = pipe;
		auto indexClose = content.lastIndexOf(")", pipe);
		if (indexClose != -1) {
			indexOpen = content.lastIndexOf("(", indexClose);
			while (indexOpen != -1) {
				if (balanced(content[indexOpen..indexClose + 1], '(', ')'))
					break;
				indexOpen = content.lastIndexOf("(", indexOpen);
			}

			if (indexOpen == -1)
				throw new ParserException("unexpected ')'", context);
		} else {
			indexClose = indexOpen;
		}

		auto tag = content[0..indexOpen];
		auto args = (indexOpen == indexClose) ? null : content[indexOpen + 1..indexClose].strip;
		if (!args.empty)
			args = "," ~ args;

		return concat("write(", filter(concat("translate(", tag, args, ")"), filters, context), ");");
	}


	auto interpolate(string content, Context context) {
		content = content.strip();
		if (content.length > 0) {
			auto filters = getSetting("defaultFilters").split(',');
			auto pipe = content.lastIndexOf("|");
			auto end = (pipe != -1) ? pipe : content.length;
			if (pipe != -1)
				filters = content[pipe + 1..$].split(',');

			content = concat("writable(", content[0..end].strip(), ")");
			return concat("write(", filter(content, filters, context), ");");
		}
		return null;
	}

	auto define(string content, Context context) {
		auto lex = Lexer(cast(ubyte[])content[1..$]);
		try {
			auto tok = lex.expect(Tok.Identifier);
			if (tok == Tok.Identifier) {
				if (lex.value == "set") {
					setSetting(lex, content, context);
				} else if (lex.value == "push") {
					pushSetting(lex, content, context);
				} else if (lex.value == "pop") {
					popSetting(lex, content, context);
				} else {
					assert(0);
				}
			}
		} catch (LexerException e) {
			throw new ParserException(e.msg, context);
		}

		return null;
	}


	void pushSetting(ref Lexer lex, string content, Context context) {
		lex.popFront;
		lex.expect(Tok.Identifier);

		auto name = lex.popValue;
		auto pstack = name in settings;
		if (!pstack)
			throw new ParserException(concat("unknown setting '", name, "'"), context);

		lex.expect(Tok.EndOfInput);

		*pstack ~= Setting(context.line, context.sourceName, (*pstack)[$ - 1].value);
	}

	void popSetting(ref Lexer lex, string content, Context context) {
		lex.popFront;
		lex.expect(Tok.Identifier);

		auto name = lex.popValue;
		auto pstack = name in settings;
		if (!pstack)
			throw new ParserException(concat("unknown setting '", name, "'"), context);

		lex.expect(Tok.EndOfInput);

		if (pstack.length < 1)
			throw new ParserException(concat("mismatching pop '", name, "' - stack is empty"), context);
		--pstack.length;
	}

	void setSetting(ref Lexer lex, string content, Context context) {
		lex.popFront;
		lex.expect(Tok.Identifier);

		auto name = lex.popValue;
		auto pstack = name in settings;
		if (!pstack)
			throw new ParserException(concat("unknown setting '", name, "'"), context);

		lex.expect(":");
		lex.popFront;
		lex.expect(Tok.Literal);

		auto literal = lex.literal;
		auto value = lex.popValue;

		lex.expect(Tok.EndOfInput);

		if (literal == Literal.String)
			value = value[1..$-1];

		(*pstack)[$ - 1] = Setting(context.line, context.sourceName, value);
	}


	string getSetting(string name) {
		if (auto psetting = name in settings)
			return (*psetting)[$ - 1].value;
		throw new Exception(concat("internal: trying to get unknown setting '", name, "'"));
	}


	auto line(string content, Context context) {
		auto info = content[1..$].strip;
		assert(info[0] == '#');
		auto infos = info[6..$].split(' ');
		context.sourceName = infos[1].unquoted;
		context.line = infos[0].to!uint;

		return concat("\n", content[1..$].strip, "\n");
	}


	auto replacer(string content, Context context) {
		if (content.length > 0) {
			auto tag = content[0..1];
			switch(tag) {
				case Tag.Iterate:
					return iterate(content, context);
				case Tag.Close:
					return close(content, context);
				case Tag.If:
					return conditional(content, context);
				case Tag.OrElse:
					return orelse(content, context);
				case Tag.Evaluate:
					return eval(content, context);
				case Tag.Translate:
					return translate(content, context);
				case Tag.LineInfo:
					return line(content, context);
				case Tag.Comment:
					return null;
				case Tag.Define:
					return define(content, context);
				case Tag.Include:
					assert(0);
				default:
					return interpolate(content, context);
			}
		}
		return null;
	}


	auto escaper(string content, Context context) {
		if (content.length) {
			if (options.compression)
			   content = compress(content, options.compression);
			return concat("write(`", content.replace("`", "\\`").replace("\r", ""), "`);");
		}
		return null;
	}

private:
	Options options;

	struct Setting {
		size_t line;
		string source;
		string value;
	}

	Setting[][string] settings;
}
