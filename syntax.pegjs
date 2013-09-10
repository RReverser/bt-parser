start = block

space = [ \t\n\r]+
eol = ";" space?

hex_digit = [0-9A-F]i
hex_number = "0x" number:hex_digit+ { return parseInt(number.join(''), 16) }
oct_number = "0" number:[0-7]+ { return parseInt(number.join(''), 8) }
bin_number = "0b" number:[01]+ { return parseInt(number.join(''), 2) }
dec_number = number:[0-9]+ { return parseInt(number.join(''), 10) }
number = hex_number / bin_number / oct_number / dec_number

string = '"' chars:char* '"' { return chars.join('') }
char
  // In the original JSON grammar: "any-Unicode-character-except-"-or-\-or-control-character"
  = [^"\\\0-\x1F\x7f]
  / '\\"'  { return '"';  }
  / "\\\\" { return "\\"; }
  / "\\/"  { return "/";  }
  / "\\b"  { return "\b"; }
  / "\\f"  { return "\f"; }
  / "\\n"  { return "\n"; }
  / "\\r"  { return "\r"; }
  / "\\t"  { return "\t"; }
  / "\\u" digits:(hex_digit hex_digit hex_digit hex_digit) {
      return String.fromCharCode(parseInt(digits, 16));
    }

name = prefix:[A-Za-z_] main:[A-Za-z_0-9]* {
	return prefix + main.join('');
}

assignment = name:name space? "=" space? expr:expression {
	return {_type: 'assignment', name: name, expr: expr};
}

args = args:(space? expr:expression space? "," { return expr })* lastArg:expression? space? {
	if (lastArg) {
		args.push(lastArg);
	}
	return args;
}

call = name:name "(" args:args ")" {
	return {_type: 'call', name: name, args: args};
}

typedef = "typedef" space type:type space name:name {
	return {_type: 'typedef', name: name, type: type};
}

struct = type:("struct" / "union") space name:name? block:bblock {
	var res = {_type: type, block: block};
	if (name) res.name = name;
	return res;
}
enum = type:"enum" space name:name? space? "{" list:args "}" {
	return {_type: type, name: name, list: list};
}
type = struct / enum / (prefix:(prefix:("unsigned" / "const") space { return prefix + ' ' })? type:name { return prefix + type })

var = type:type space name:name repeat:(space? "[" expr:expression? "]" { return expr || Infinity })? initial:(space? "=" expr:expression { return expr })? {
	var res = {_type: 'var', name: name, type: type};
	if (repeat) {
		res.repeat = repeat;
	}
	if (initial) {
		res.initial = initial;
	}
	return res;
}

expression = space? expr:(call / assignment / name:name { return {_type: 'ref', name: name} } / number / string) { return expr }
statement = space? stmt:(typedef / var / enum / struct / expression) eol { return stmt }
block = statement*
bblock = space? "{" block:block "}" { return block }