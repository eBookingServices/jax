module templ;


template locals(size_t i, Vars...) {
	import std.conv : to;
	static if(i < Vars.length) {
		enum string locals = Vars.length ? "alias Vars[" ~ to!string(i) ~ "] " ~ __traits(identifier, Vars[i]) ~ ";\n" ~ locals!(i + 1, Vars) : null;
	} else {
		enum string locals = "";
	}
}


void render(OutputStreamTy, string FileName, Vars...)(OutputStreamTy o__, string language__) {
	void write(Ty)(Ty x) { // required
		o__.write(x);
	}

	auto translate(Ty, Args...)(Ty tag, Args args) { // required
		assert(language__ == "en");
		switch (tag) {
			case "footer":	return "This is the footer translation";
			case "empty":	return "Move along, nothing to see here";
			default: return tag;
		}
	}

	auto writable(Ty)(in Ty x) { // required - all interpolations go through this
		import std.conv : to;
		import std.traits : OriginalType;
		static if (is(Ty == enum)) {
			return to!string(cast(OriginalType!Ty)x);
		} else {
			return to!string(x);
		}
	}

	// symbols available globally for all templates
	// add more as you wish
	import std.algorithm;
	import std.array;
	import std.conv : to;
	import std.string;
	import std.uni : toUpper, toLower;

	import jax.filters; // the default run-time filter implementation

	mixin(locals!(0, Vars));
	mixin(import(FileName ~ ".d.mixin"));
}
