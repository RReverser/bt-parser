{
  function join(nameParts) {
    return nameParts instanceof Array ? nameParts.map(join).join('') : nameParts;
  }
}

start = block

space = [ \t\n\r]+
eol = ";" space?
number = all:(("0x" [0-9A-Fa-f]+) / [0-9]+) {
	return Number(join(all));
}
name = all:([A-Za-z_][A-Za-z_0-9]*) {
	return join(all);
}
assignment = name:name repeat:("[" number:number? "]" { return number !== '' ? number : Infinity })? space? expr:("=" expr:expression { return expr })? {
	var obj = {name: name};
	if (repeat) {
		obj.repeat = repeat;
	}
	if (expr) {
		obj.expr = expr;
	}
	return obj;
}
type = typedef / name
typedef = struct / enum
var = type:type space expr:assignment {
	return {type: type, expr: expr};
}
args = args:(expr:expression "," { return expr })* lastArg:expression? {
	args.push(lastArg);
	return args;
}
call = name:name space? "(" args:args ")" {
	return {name: name, args: args};
}
expression = space? expr:(call / assignment / number) { return expr }
statement = space? stmt:(typedef / call / var) eol { return stmt }
block = statement*
wrapped_block = "{" block:block "}" { return block }
struct = "struct" space name:name space? block:wrapped_block { return {name: name, block: block} }
enum = "enum" space name:name space? "{" args:args "}" {
	args.reduce(function (lastValue, arg) {
		return 'expr' in arg ? arg.expr : (arg.expr = lastValue + 1);
	}, -1);
	return {name: name, enum: args};
}