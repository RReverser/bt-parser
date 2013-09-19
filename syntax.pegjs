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

			this.__end__ = {line: line(), column: column() - 1};

			return instance;
		}

		Class.prototype = proto || {};
		Class.prototype.type = type;
		Class.prototype.constructor = Class;
		Class.prototype.__init__ = init;
		Class.prototype.at = function (start, end) {
			this.loc = {start: start, end: end || this.__end__};
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
	).at(block.loc.start);
}

pos = { return {line: line(), column: column() - 1} }

space_char = [ \t\n\r]
_ = space_char*
__ = space_char+
eol = ";" _

hex_digit = [0-9A-F]i

hex_number = "0x" number:$(hex_digit+) { return parseInt(number, 16) }
oct_number = "0" number:$([0-7]+) { return parseInt(number, 8) }
bin_number = "0b" number:$([01]+) { return parseInt(number, 2) }
dec_number = number:$([0-9]+) { return parseInt(number, 10) }

number = start:pos number:(hex_number / bin_number / oct_number / dec_number) _ { return literal(number).at(start) }

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

string = start:pos '"' chars:$(char*) '"' _ { return literal(chars).at(start) }

name = start:pos name:$([A-Za-z_] [A-Za-z_0-9]*) _ { return id(name).at(start) }
indexed = start:pos name:name index:("[" expr:expression? "]" _ { return expr }) { return member(name, index, true).at(start) }
ref = indexed / name

assignment = start:pos ref:ref "=" _ expr:expression { return assign(ref, expr).at(start) }

struct = start:pos type:("struct" / "union") __ name:name? bblock:bblock {
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
	).at(bblock.loc.start);

	var expr = call(member(id('jBinary'), id('Type')), [
		obj({
			key: id('read'),
			value: func([], bblock)
		})
	]);

	if (name) {
		expr = assign(member(member(id('$BINARY'), id('typeSet')), name).at(name.loc.start, name.loc.end), expr.at(bblock.loc.start));
	}

	return expr.at(start);
}

type = struct / start:pos prefix:(prefix:"unsigned" __ { return prefix + ' ' })? name:name { return literal(prefix + name.name).at(start) }

expression = assignment / call / ref / string / number

args = args:(start:pos ref:ref "," _ { return ref.at(start) })* last:ref? {
	if (last) args.push(last);
	return args;
}

call = start:pos ref:ref "(" _ args:args ")" _ {
	args.unshift(id('$BINARY'));
	return call(member(ref, id('call')).at(ref.loc.start, ref.loc.end), args).at(start);
}

var_file = start:pos type:type ref:ref {
	if (ref instanceof member) {
		type = array(literal('array'), type, ref.property || id('undefined')).at(type.loc.start, type.loc.end);
		ref = ref.object.at(ref.loc.start, ref.loc.end);
	}

	return assign(
		member(id('$RESULT'), ref).at(ref.loc.start, ref.loc.end),
		call(
			member(id('$BINARY'), id('read')),
			[type]
		).at(type.loc.start, type.loc.end)
	).at(start);
}

var_local = start:pos kind:("local" / "const") __ type:type ref:(assignment / ref) {
	return vars({
		id: ref instanceof assign ? ref.left : ref,
		init: ref.right
	}).at(start);
}

var = var_local / var_file

statement = expr:(var / struct / expression) eol {
	return /Expression$/.test(expr.type) ? stmt(expr) : expr;
}

block = start:pos stmts:statement* {
	return block.apply(null, stmts).at(start);
}

bblock = start:pos "{" _ block:block "}" _ { return block.at(start) }