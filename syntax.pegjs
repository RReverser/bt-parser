{
	function def(type, init, proto) {
		function Class() {
			var instance = Object.create(Class.prototype),
				args = Array.prototype.slice.call(arguments),
				init = instance.__init__;

			switch (typeof init) {
				case 'function':
					init.apply(instance, args);
					break;

				case 'string':
					instance[init] = args;
					break;

				default:
					init.forEach(function (key, i) {
						if (args[i] !== undefined) {
							instance[key] = args[i];
						}
					});
					break;
			}

			return instance;
		}

		Class.prototype = proto || {};
		Class.prototype.type = type;
		Class.prototype.constructor = Class;
		Class.prototype.__init__ = init;
		Class.prototype.at = function (start, end) {
			this.loc = {start: start, end: end};
			return this;
		}
		Class.prototype.toString = function () { return '[' + this.type + ']' };

		return Class;
	}

	var program = def('Program', 'body');
	var id = def('Identifier', ['name']);
	var member = def('MemberExpression', ['object', 'property', 'computed']);
	var literal = def('Literal', ['value']);
	var obj = def('ObjectExpression', function () {
		this.properties = Array.prototype.map.call(arguments, function (property) {
			property.type = 'Property';
			return property /* key, value */;
		});
	});
	var assign = def('AssignmentExpression', ['left', 'right'], {operator: '='});
	var call = def('CallExpression', ['callee', 'arguments'], {arguments: []});
	var vars = def('VariableDeclaration', function () {
		this.declarations = Array.prototype.map.call(arguments, function (declaration) {
			declaration.type = 'VariableDeclarator';
			return declaration /* id, init */;
		});
	}, {kind: 'var'});
	var inContext = def('WithStatement', ['object', 'body']);
	var stmt = def('ExpressionStatement', ['expression']);
	var block = def('BlockStatement', 'body');
	var ret = def('ReturnStatement', ['argument']);
	var func = def('FunctionExpression', ['params', 'body']);
	var array = def('ArrayExpression', 'elements');
}

start = block:block {
	return program(
		vars({id: id('$RESULT'), init: obj()}),
		inContext(id('$RESULT'), block)
	);
}

space_char = [ \t\n\r]
_ = space_char*
__ = space_char+
eol = ";" _

hex_digit = [0-9A-F]i

hex_number = "0x" number:$(hex_digit+) { return parseInt(number, 16) }
oct_number = "0" number:$([0-7]+) { return parseInt(number, 8) }
bin_number = "0b" number:$([01]+) { return parseInt(number, 2) }
dec_number = number:$([0-9]+) { return parseInt(number, 10) }

number = number:(hex_number / bin_number / oct_number / dec_number) _ { return literal(number) }

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
  / "\\u" digits:$(hex_digit hex_digit hex_digit hex_digit) {
	  return String.fromCharCode(parseInt(digits, 16));
	}

string = '"' chars:$(char*) '"' _ { return literal(chars) }

name = name:$([A-Za-z_] [A-Za-z_0-9]*) _ { return id(name) }
indexed = name:name index:("[" expr:expression? "]" _ { return expr }) { return member(name, index, true) }
ref = indexed / name

assignment = ref:ref "=" _ expr:expression { return assign(ref, expr) }

struct = type:("struct" / "union") __ name:name? bblock:bblock {
	if (type === 'union') {
		var newBody = [
			vars({
				id: id('$START'),
				init: call(member(id('$BINARY'), id('tell')))
			})
		];

		var seekBack = stmt(call(
			member(id('$BINARY'), id('seek')),
			[id('$START')]
		));

		bblock.body.forEach(function (stmt, index) {
			if (index > 0) newBody.push(seekBack);
			newBody.push(stmt);
		});

		bblock.body = newBody;
	}

	bblock = block(
		vars({id: id('$RESULT'), init: obj()}),
		inContext(id('$RESULT'), bblock),
		ret(id('$RESULT'))
	);

	var expr = call(member(id('jBinary'), id('Type')), [
		obj({
			key: id('read'),
			value: func([], bblock)
		})
	]);

	if (name) {
		expr = assign(member(member(id('$BINARY'), id('typeSet')), name), expr);
	}

	return expr;
}

type = struct / prefix:(prefix:"unsigned" __ { return prefix + ' ' })? name:name { return literal(prefix + name.name) }

expression = assignment / call / ref / string / number

args = args:(ref:ref "," _ { return ref })* last:ref? {
	if (last) args.push(last);
	return args;
}

call = ref:ref "(" _ args:args ")" _ {
	args.unshift(id('$BINARY'));
	return call(member(ref, id('call')), args);
}

var_file = type:type ref:ref {
	return assign(
		member(id('$RESULT'), ref instanceof member ? ref.object : ref),
		call(
			member(id('$BINARY'), id('read')),
			[ref instanceof member ? array(literal('array'), type, ref.property || id('undefined')) : type]
		)
	);
}

var_local = kind:("local" / "const") __ type:type ref:(assignment / ref) {
	return vars({
		id: ref instanceof assign ? ref.left : ref,
		init: ref.right
	});
}

var = var_local / var_file

statement = expr:(var / struct / expression) eol {
	return /Expression$/.test(expr.type) ? stmt(expr) : expr;
}

block = stmts:statement* {
	return block.apply(null, stmts);
}

bblock = "{" _ block:block "}" _ { return block }