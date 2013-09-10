start = block

space = [ \t\n\r]+
eol = ";" space?
hex_number = "0x" number:[0-9A-F]i+ { return parseInt(number.join(''), 16) }
oct_number = "0" number:[0-7]+ { return parseInt(number.join(''), 8) }
bin_number = "0b" number:[01]+ { return parseInt(number.join(''), 2) }
dec_number = number:[0-9]+ { return parseInt(number.join(''), 10) }
number = hex_number / bin_number / oct_number / dec_number
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
type = struct / enum / (prefix:(("unsigned" / "const") space)? type:name { return prefix + type })
var_init = type:type space assignment:assignment {
	assignment._type = 'var';
	assignment.type = type;
	return assignment;
}
var_simple = type:type space name:name {
	return {_type: 'var', name: name, type: type};
}
var = var_init / var_simple
struct = type:("struct" / "union") space name:name? block:bblock {
	var res = {_type: type, block: block};
	if (name) res.name = name;
	return res;
}
enum = type:"enum" space name:name? space? "{" list:args "}" {
	return {_type: type, name: name, list: list};
}
typedef = "typedef" space type:type space name:name {
	return {_type: 'typedef', name: name, type: type};
}
expression = space? expr:(call / assignment / name / number) { return expr }
statement = space? stmt:(typedef / var / enum / struct / expression) eol { return stmt }
block = statement*
bblock = space? "{" block:block "}" { return block }