### Jax - Mustache-like template compiler for D

Jax has been written mainly for use with vibe.d but it can be used in any other way.

Compiles source text/html into valid D source code ready for use as a mixin.

### Features
- HTML compressor
- Parametrized macros
- Good and detailed error reporting
- Supports languages
- Can automatically re-compile known dependant files
- Token-based cache-busting mechanism
- Interpolation and translation tags will escape HTML by default


#### Options
	o|output-dir - Output directory
	p|time - Display elapsed time at end
	v|verbose - Verbose output
	l|line-numbers - Keep line numbers for error reporting (disables compression)
	d|dep-cache - Dependant-cache directory
	g|dep-gen-only - Only generate dependant-cache, do not re-compile dependants
	c|compress - Compress HTML in between template tags
	j|search - Search path(s) to look for dependency files
	t|token	- Token for token_url interpolation filter. Useful for cache-busting
	

#### Tags
	{{& fileName}} - Include external file
	{{&& fileName}} - Embed external file as mime-encoded content
	{{* it; iterable}}{{/}} - Iterate object, array or otherwise iteratable symbol - implemeted as foreach in D
	{{? condition}} true case {{: [condition] }} else case {{/}}
	{{% D code }} - Evaluate D code
	{{! comment}} - Comment
	{{ symbol | filters }} - Interpolate symbol as to output
	{{~ "message-id"(["name": "moo"]) | filters }} - Translate message-id with arguments
	{{# def myMacro(arg)}} macro text {{# arg}} {{#/}}
	{{# macroMacro("mooo")}} - Call a macro
	
#### Filters
	none - Does nothing
	lower - Lower case
 	upper - Upper case
 	html - Escape for HTML
 	format_html - Escape for HTML and replace LF with </br>
 	format_html_links - Escape HTML, replace LF with </br> and create links for URL-like text
 	js - Escape for Javascript
 	url - Escape for URL
	token_url - Appends v=<token> query parameter to url
  

Check the example directory for a working example.


#### TODO
- add means to remove whitespace in-between template-tags
- add more configuration options
- improve HTML compressor
- profile and optimize
