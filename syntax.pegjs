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
		Object.defineProperty(Class.prototype, '__init__', {value: init});
		Class.prototype.at = function (start, end) {
			this.loc = {start: start, end: end};
			return this;
		};
		Class.prototype.toString = function () { return '[' + this.type + ']' };
		Class.prototype.toJSON = function () {
			var tmp = {};
			for (var key in this) {
				tmp[key] = this[key];
			}
			return tmp;
		};

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
	var assign = def('AssignmentExpression', ['left', 'right', 'operator'], {operator: '='});
	var update = def('UpdateExpression', ['argument', 'operator', 'prefix']);
	var call = def('CallExpression', ['callee', 'arguments'], {arguments: []});
	var create = def('NewExpression', ['callee', 'arguments'], {arguments: []});
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
	var binary = def('BinaryExpression', ['left', 'operator', 'right']);
	var unary = def('UnaryExpression', ['operator', 'argument'], {prefix: true});
	var cond = def('ConditionalExpression', ['test', 'consequent', 'alternate']);
}

start = block:block {
	return program(
		vars({id: id('$RESULT'), init: obj()}),
		inContext(id('$RESULT'), block)
	);
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

literal = string / number

name = name:$([A-Za-z_] [A-Za-z_0-9]*) _ { return id(name) }
indexed = name:name index:("[" expr:expr? "]" _ { return expr }) { return member(name, index, true) }
ref = indexed / name

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

// Looks like mess, but at least provides correct precedence for supported operators.
// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Operator_Precedence
group = "(" expr:expr ")" _ { return expr }
expr_0 = literal / group
expr_1 = ref / expr_0
expr_2 = call / expr_1
op_update = op:("++" / "--") _ { return op }
expr_3 =
	  op:op_update ref:ref { return update(ref, op, true) }
	/ ref:ref op:op_update { return update(ref, op) }
	/ expr_2
expr_4 =
	  op:[!~+-] _ expr:expr_3 { return unary(op, expr) }
	/ expr_3
expr_5 =
	  left:expr_4 op:[*/%] _ right:expr_5 { return binary(left, op, right) }
	/ expr_4
expr_6 =
	  left:expr_5 op:[+-] _ right:expr_6 { return binary(left, op, right) }
	/ expr_5
expr_7 =
	  left:expr_6 op:("<<" / ">>") _ right:expr_7 { return binary(left, op, right) }
	/ expr_6
expr_8 =
	  left:expr_7 op:$([<>] "="?) _ right:expr_8 { return binary(left, op, right) }
	/ expr_7
expr_9 =
	  left:expr_8 op:$([!=] "=") _ right:expr_9 { return binary(left, op, right) }
	/ expr_8
expr_10 =
	  left:expr_9 op:"&" _ right:expr_10 { return binary(left, op, right) }
	  / expr_9
expr_11 =
	  left:expr_10 op:"^" _ right:expr_11 { return binary(left, op, right) }
	  / expr_10
expr_12 =
	  left:expr_11 op:"|" _ right:expr_12 { return binary(left, op, right) }
	  / expr_11
expr_13 =
	  left:expr_12 op:"&&" _ right:expr_13 { return binary(left, op, right) }
	  / expr_12
expr_14 =
	  left:expr_13 op:"||" _ right:expr_14 { return binary(left, op, right) }
	  / expr_13
expr_15 =
	  test:expr_14 "?" _ good:expr_14 ":" _ bad:expr_15 { return cond(test, good, bad) }
	/ expr_14
op_assign = op:$(("<<" / ">>" / [%|^&*/+-])? "=") _ { return op }
assignment = ref:ref op:op_assign _ expr:expr { return assign(ref, expr, op) }
expr = assignment / expr_15

args = args:(ref:ref "," _ { return ref })* last:ref? {
	if (last) args.push(last);
	return args;
}

call = ref:ref "(" _ args:args ")" _ {
	args.unshift(id('$BINARY'));
	return call(member(ref, id('call')), args);
}

var_file = type:type ref:ref {
	return stmt(assign(
		member(id('$RESULT'), ref instanceof member ? ref.object : ref),
		call(
			member(id('$BINARY'), id('read')),
			[ref instanceof member ? array(literal('array'), type, ref.property || id('undefined')) : type]
		)
	));
}

var_local = ("local" / "const") __ type:type ref:(assignment / ref) {
	return vars(
		ref instanceof assign
			? {id: ref.left instanceof member ? ref.left.object : ref.left, init: ref.right}
			: ref instanceof member
				? {id: ref.object, init: ref.property ? create(id('Array'), [ref.property]) : array()}
				: {id: ref}
	);
}

var = var_local / var_file

statement = stmt:(var / expr:(struct / expr) { return stmt(expr) }) eol {
	return stmt;
}

block = stmts:statement* {
	return block.apply(null, stmts);
}

bblock = "{" _ block:block "}" _ { return block }