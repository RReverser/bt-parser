{
	var types = {};
	function process(block) {
		var context = {};
		block.filter(Boolean).forEach(function (item) {
			context[item.name] = item.type;
		});
		return context;
	}
	var autoIncrement = (function () {
		var current = 0;
		return function () { return current++ };
	})();
}

start = block:block {
	types['jBinary.all'] = process(block);
	return types;
}

___char = [ \t\n\r]
_ = ___char*
__ = ___char+
eol = ";" _

hex_digit = [0-9A-F]i
hex_number = "0x" number:hex_digit+ { return parseInt(number.join(''), 16) }
oct_number = "0" number:[0-7]+ { return parseInt(number.join(''), 8) }
bin_number = "0b" number:[01]+ { return parseInt(number.join(''), 2) }
dec_number = number:[0-9]+ { return parseInt(number.join(''), 10) }
number = hex_number / bin_number / oct_number / dec_number

string = '"' chars:char* '"' _ { return chars.join('') }
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

name = prefix:[A-Za-z_] main:[A-Za-z_0-9]* _ {
	return prefix + main.join('');
}

ref = name:name index:("[" expr:expression? "]" _ { return expr !== '' ? expr : Infinity })? {
	var res = {_type: 'ref', name: name, type: ['ref', name]};
	if (index !== '') {
		res.index = index;
		res.type.push(index);
	}
	return res;
}

assignment = ref:ref "=" _ expr:expression {
	return {_type: 'assignment', ref: ref, expr: expr};
}

struct = type:("struct" / "union") __ name:name? block:bblock {
	block = process(block);
	if (name) types[name] = block;
	return type === 'struct' ? block : [type, block];
}

type = struct / prefix:(prefix:"unsigned" __ { return prefix + ' ' })? name:name { return prefix + name }
expression = call / ref / string / number
args = args:(ref:ref "," _ { return ref })* last:ref? {
	if (last) {
		args.push(last);
	}
	return args;
}
call = name:name "(" _ args:args ")" _ {
	return {_type: 'call', name: '_call_' + autoIncrement(), type: ['call', name, args]};
}
var_file = type:type ref:ref {
	var baseType = type;
	if ('index' in ref) {
		type = ['array', baseType];
		if (ref.index !== Infinity) {
			type.push(ref.index);
		}
	}
	return {_type: 'var', name: ref.name, type: type};
}
var_local = ("local" / "const") __ type:type ref:(assignment / ref) {
	var baseType = type, value;
	if (ref._type === 'assignment') {
		value = ref.expr;
		ref = ref.ref;
	}
	if ('index' in ref) {
		type = ['array', baseType];
		if (ref.index !== Infinity) {
			type.push(ref.index);
		}
	}
	type = ['local', type];
	if (value !== undefined) {
		if (typeof value === 'object' && '_type' in value) {
			type = value.type;
		} else {
			type.push(value);
		}
	}
	return {_type: 'var', name: ref.name, type: type};
}
var = var_local / var_file
statement = stmt:(var / struct {} / expression) eol { return stmt }
block = statement*
bblock = "{" _ block:block "}" _ { return block }