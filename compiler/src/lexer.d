module lexer;


import std.ascii;
import std.array;
import std.exception;
import std.string;


class LexerException : Throwable {
	this(Lexer.State state, string msg) {
		super(msg);
		this.state = state;
	}

	Lexer.State state;
}


enum Tok : ubyte {
	Invalid = 0,
	EndOfInput,
	Char,
	Literal,
	Identifier,
}


enum Literal : ubyte {
	None = 0,
	Decimal,
	Hex,
	Float,
	String,
}


struct Lexer {
	this(ubyte[] source) {
		state.original = source;
		state.source = source;
		state.tok = Tok.Invalid;
		state.literal = Literal.None;
		popFront;
	}

	Tok next() {
		popFront;
		return state.tok;
	}

	string nextValue() {
		popFront;
		return cast(string)state.value;
	}

	Tok pop() {
		Tok tok = state.tok;
		popFront;
		return tok;
	}

	string popValue() {
		string value = cast(string)state.value;
		popFront;
		return value;
	}

	void popFront() {
		expectNot(Tok.EndOfInput);

		auto cursor = state.source.ptr;
		auto end = state.source.ptr + state.source.length;

		skipWhites(cursor, end);
		scope(exit) {
			skipWhites(cursor, end);
			state.source = state.source[cursor - state.source.ptr..$];
		}

		while (cursor != end) {
			auto tokStart = cursor;
			state.start = cast(size_t)(tokStart - state.source.ptr);
			state.literal = Literal.None;

			auto ch = *cursor++;

			switch(ch) {
				case '.':
				case '0': .. case '9':
					if ((ch == '.') && !isDigit(*cursor))
						goto default;

					auto suffix = false;
					state.tok = Tok.Literal;
					state.literal = (ch == '.') ? Literal.Float : Literal.Decimal;

					while (cursor != end) {
						ch = *cursor;
						switch(ch) {
							case '_':
								enforce(*(cursor - 1) != '_', cursor, "unexpected digit grouping '_' in literal");
								++cursor;
								continue;
							case '.':
								enforce(state.literal != Literal.Hex, cursor, "unexpected '.' in hex literal");
								auto next = std.ascii.toLower(peek(cursor, 1, end));
								if (next && !isDigit(next) && (next != 'f'))
									break;
								enforce(state.literal != Literal.Float, cursor, "unexpected '.' in float literal");
								state.literal = Literal.Float;
								++cursor;
								continue;
							case 'x':
								enforce(state.literal != Literal.Hex, cursor, "unexpected second 'x' in hex literal");
								enforce((*(cursor - 1) == '0') && (cursor - 1 == tokStart), cursor, "unexpected 'x' in numeric literal");
								state.tok = Tok.Literal;
								state.literal = Literal.Hex;
								tokStart += 2;
								++cursor;
								continue;
							default:
								if (isDigit(ch)) {
									++cursor;
									continue;
								} else if (isAlpha(ch)) {
									if (state.literal == Literal.Hex) {
										ch = std.ascii.toLower(*cursor);
										enforce((ch >= 'a') && (ch <= 'f'), cursor, "unexpected '%c' in hex literal", cast(char)ch);
										++cursor;
										continue;
									} else if ((state.literal == Literal.Float) && (ch == 'f')) {
										++cursor;
										suffix = true;
										break;
									}
									enforce(isWhite(ch), cursor, "unexpected '%c' in literal", cast(char)*cursor);
								}
								break;
						}
						break;
					}
					state.value = tokStart[0..cursor - tokStart - (suffix ? 1 : 0)];
					return;
				case '"': case '\'': case '`':
					cursor = skipUntil(cursor, end, ch, ch != '`');
					enforce(*cursor == ch, cursor, "unexpected end of input in string literal");
					++cursor;
					state.value = tokStart[0..cursor - tokStart];
					state.tok = Tok.Literal;
					state.literal = Literal.String;
					return;
				case 'a': .. case 'z':
				case 'A': .. case 'Z':
				case '_':
					while ((cursor != end) && (isAlphaNum(*cursor) || (*cursor == '_')))
						++cursor;
					state.value = tokStart[0..cursor - tokStart];
					state.tok = Tok.Identifier;
					return;
				default:
					if (isASCII(ch)) {
						state.value = tokStart[0..cursor - tokStart];
						state.tok = Tok.Char;
						return;
					}
					break;
			}
		}

		state.tok = Tok.EndOfInput;
	}

	bool empty() nothrow {
		return state.tok == Tok.EndOfInput;
	}

	Tok front() nothrow {
		return state.tok;
	}

	Literal literal() nothrow {
		return state.literal;
	}

	string value() nothrow {
		return cast(string)state.value;
	}

	string remaining() nothrow {
		return cast(string)state.source;
	}

	size_t cursor() nothrow {
		return state.original.length - state.source.length;
	}

	Tok popUntil(Args...)(auto ref Args args) {
		while (true) {
			auto tok = next;
			foreach(i, Arg; Args) {
				static assert(is(Arg == Tok) || is(Arg == string));
				static if (is(Arg == Tok)) {
					if (state.tok == args[i])
						return state.tok;
				} else static if (is(Arg == string)) {
					if ((state.tok == Tok.Char) && (state.value == args[i]))
						return state.tok;
				}
			}
		}

		import std.format;
		Appender!string exception;

		foreach(i, arg; args) {
			if (i == 0) {
				formattedWrite(&exception, "expected '%s'", arg);
			} else if (i + 1 == args.length) {
				formattedWrite(&exception, ", or '%s'", arg);
			} else {
				formattedWrite(&exception, ", '%s'", arg);
			}
		}

		if (state.tok == Tok.Char) {
			formattedWrite(&exception, " but found '%s'", state.value);
		} else {
			formattedWrite(&exception, " but found '%s'", state.tok);
		}

		throw new LexerException(state, exception.data);
		return state.tok;
	}

	Tok popUntilBalanced(string close, string open) {
		assert(value == open);
		assert(close != open);

		size_t opened = 1;
		while (opened) {
			popFront;
			if (state.tok == Tok.Char) {
				if (state.value == close) {
					if (opened > 0)
						--opened;
				} else if (state.value == open) {
					++opened;
				}
			} else if (state.tok == Tok.EndOfInput) {
				expectNot(Tok.EndOfInput);
			}
		}

		return state.tok;
	}

	auto expectNot(Args...)(auto ref Args args) {
		foreach(i, Arg; Args) {
			static assert(is(Arg == Tok) || is(Arg == string));
			static if (is(Arg == Tok)) {
				if (state.tok != args[i])
					continue;
			} else static if (is(Arg == string)) {
				if ((state.tok != Tok.Char) || (state.value != args[i]))
					continue;
			}

			{
				static if (is(Arg == Tok)) {
					throw new Exception(format("unexpected '%s'", args[i]));
				} else {
					throw new Exception(format("unexpected '%s'", state.value));
				}
			}
		}

		return state.tok;
	}

	auto expect(Args...)(auto ref Args args) {
		foreach(i, Arg; Args) {
			static assert(is(Arg == Tok) || is(Arg == string));
			static if (is(Arg == Tok)) {
				if (state.tok == args[i])
					return state.tok;
			} else static if (is(Arg == string)) {
				if ((state.tok == Tok.Char) && (state.value == args[i]))
					return state.tok;
			}
		}

		import std.format;
		Appender!string exception;

		foreach(i, arg; args) {
			if (i == 0) {
				formattedWrite(&exception, "expected '%s'", arg);
			} else if (i + 1 == args.length) {
				formattedWrite(&exception, ", or '%s'", arg);
			} else {
				formattedWrite(&exception, ", '%s'", arg);
			}
		}

		if (state.tok == Tok.Char) {
			formattedWrite(&exception, " but found '%s'", state.value);
		} else {
			formattedWrite(&exception, " but found '%s'", state.tok);
		}

		throw new LexerException(state, exception.data);
	}

	int opApply(scope int delegate(Tok tok, string val) del) {
		while(!empty) {
			auto tok = state.tok;
			auto value = cast(string)state.value;
			popFront;
			if (auto ret = del(tok, value))
				return ret;
		}
		return 0;
	}

	int opApply(scope int delegate(Tok tok, Literal literal, string val) del) {
		while(!empty) {
			auto tok = state.tok;
			auto value = cast(string)state.value;
			auto literal = state.literal;
			popFront;
			if (auto ret = del(tok, literal, value))
				return ret;
		}
		return 0;
	}

private:
	ubyte peek(ubyte* cursor, int offset, ubyte* end) {
		auto ptr = cursor + offset;
		if (ptr < end)
			return *ptr;
		return 0;
	}

	ref ubyte* skipWhites(ref ubyte* cursor, ubyte* end) {
		while ((cursor != end) && isWhite(*cursor)) {
			if (*cursor == '\n') {
				++state.line;
				state.lineStart = cast(size_t)((cursor + 1) - state.source.ptr);
			}
			++cursor;
			state.source = state.source[cursor - state.source.ptr..$];
		}
		return cursor;
	}

	ref ubyte* skipUntil(ref ubyte* cursor, ubyte* end, ubyte ch, bool escape = false) {
		while ((cursor != end) && (*cursor != ch)) {
			if (escape && (*cursor == '\\')) {
				++cursor;
				enforce(cursor != end, cursor, "incomplete escape sequence", cast(char)*cursor);
			}
			if (*cursor == '\n') {
				++state.line;
				state.lineStart = cast(size_t)((cursor + 1) - state.source.ptr);
			}
			++cursor;
			state.source = state.source[cursor - state.source.ptr..$];
		}
		return cursor;
	}

	void enforce(Args...)(bool value, ubyte* cursor, string fmt, Args args) {
		if (!value) {
			state.offset = cast(size_t)(cursor - state.source.ptr);
			throw new LexerException(state, format(fmt, args));
		}
	}

	struct State {
		size_t line;
		size_t lineStart;
		size_t start;
		size_t offset;
		ubyte[] original;
		ubyte[] source;
		ubyte[] value;
		Tok tok = Tok.EndOfInput;
		Literal literal = Literal.None;
	}

	State state;
}



void testLexer() {
	import std.stdio;
	void expect(string source, Tok tok, string value, bool one = true) {
		auto lex = Lexer(cast(ubyte[])source);
		assert(lex.front == tok);
		assert(lex.value == value);
		if (one) {
			lex.popFront;
			assert(lex.empty);
		}
	}

	void expectException(string source) {
		try {
			auto lex = Lexer(cast(ubyte[])source);
		} catch (LexerException e) {
			return;
		}
		assert(false);
	}

	expect("foo", Tok.Identifier, "foo");
	expect("_foo", Tok.Identifier, "_foo");
	expect("_fo_o_", Tok.Identifier, "_fo_o_");

	expect(`"foo"`, Tok.Literal, `"foo"`);
	expect(`'foo'`, Tok.Literal, `'foo'`);

	expect("1337", Tok.Literal, "1337");
	expect("13_37", Tok.Literal, "13_37");
	expect("0xbeef", Tok.Literal, "beef");
	expect("1.0", Tok.Literal, "1.0");
	expect("1.0f", Tok.Literal, "1.0");
	expect(".1", Tok.Literal, ".1");
	expect(".1f", Tok.Literal, ".1");
	expect("1.", Tok.Literal, "1.");
	expect("1.f", Tok.Literal, "1.");
	expect("1..", Tok.Literal, "1", false);
	expect("1...", Tok.Literal, "1", false);
	expect("1[]", Tok.Literal, "1", false);
	expect("123[]", Tok.Literal, "123", false);
	expect("1.h", Tok.Literal, "1", false);

	expect(".", Tok.Char, ".");
	expect("(", Tok.Char, "(");
	expect("+", Tok.Char, "+");

	expectException(`"foo`);
	expectException(`'foo`);
	expectException(`1__2`);
	expectException(`0xabcdefg`);
	expectException(`1.0h`);
}

unittest {
	testLexer();
}
