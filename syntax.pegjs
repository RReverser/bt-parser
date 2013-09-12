{
	var customTypes = {}, mappings = [];
	function customType(name, definition) {
		customTypes[name] = true;
		return (name ? '__types.' + name + '=' : '') + definition;
	}
	function map(line, column, js) {
		if (typeof js !== 'object') {
			js = {
				value: js,
				toString: function () {
					return this.value.toString();
				}
			};
		}
		js.line = line;
		js.column = column;
		return js;
	}
}

start = block:block {
	return ['(function () {var __result={},__types={};', block, 'return __result;})()'];
}

space_char = [ \t\n\r]
_ = space_char*
__ = space_char+
eol = ";" _

hex_digit = [0-9A-F]i
hex_number = "0x" number:hex_digit+ { return parseInt(number.join(''), 16) }
oct_number = "0" number:[0-7]+ { return parseInt(number.join(''), 8) }
bin_number = "0b" number:[01]+ { return parseInt(number.join(''), 2) }
dec_number = number:[0-9]+ { return parseInt(number.join(''), 10) }
number = hex_number / bin_number / oct_number / dec_number

string = '"' chars:char* '"' _ { return JSON.stringify(chars.join('')) }
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
      return String.fromCharCode(parseInt(digits.join(''), 16));
    }

name = prefix:[A-Za-z_] main:[A-Za-z_0-9]* _ {
	return {
		name: prefix + main.join(''),
		toString: function () {
			return this.name;
		}
	};
}

indexed = name:name index:("[" expr:expression? "]" { return expr }) {
	return {
		name: name,
		index: index,
		toString: function () {
			return this.name + '[' + this.index + ']';
		}
	};
}

ref = indexed / name

assignment = ref:ref "=" _ expr:expression {
	return ref + '=' + expr;
}

struct = type:("struct" / "union") __ name:name? block:bblock {
	if (type === 'union') {
		block = ['var __start=binary.tell();'].concat(block.map(function (stmt, index) {
			return (index ? 'binary.seek(__start);' : '') + stmt;
		}));
	}
	return customType(name, 'jBinary.Type({read:function(){var __result={};' + block.join('') + 'return __result;}})');
}

type = struct / prefix:(prefix:"unsigned" __ { return prefix + ' ' })? name:name {
	name = prefix + name;
	return name in customTypes ? '__types.' + name : JSON.stringify(name);
}
expression = call / ref / string / number
args = args:(ref:ref "," _ { return ref })* last:ref? {
	if (last) {
		args.push(last);
	}
	return args;
}
call = name:name "(" _ args:args ")" _ {
	return 'std010.' + name + '.call(' + ['binary'].concat(args) + ')';
}
var_file = type:type ref:ref {
	return 'var ' + ref.name + '=__result.' + ref.name + '=binary.read(' + (
		'index' in ref
		? '["array",' + type + (ref.index ? ',' + ref.index : '') + ']'
		: type
	) + ')'
}
var_local = ("local" / "const") __ type:type ref:(assignment / ref) {
	return 'var ' + ref;
}
var = var_local / var_file
statement = stmt:(var / struct / expression) eol { return map(line, column, stmt + ';') }
block = stmts:statement* { return stmts }
bblock = "{" _ block:block "}" _ { return block }