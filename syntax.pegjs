{
	var customTypes = {};

	function def(type, args, init) {
		var constructor = function () {
			if (!(this instanceof constructor)) {
				return (new constructor).set(arguments);
			}
			this.set(arguments);
		};
		constructor.prototype = {
			type: type,
			init: init || function(){},
			defaults: args || [],
			set: function (args) {
				this.defaults.forEach(function (key) {
					this[key] = args[i];
				}, this);
				this.init();
				return this;
			}
		};
		return constructor;
	}

	var id = def('Identifier', ['name']);
	var member = def('MemberExpression', ['object', 'property']);
	var literal = def('Literal', ['value']);
	var obj = def('ObjectExpression', ['properties']);
	var prop = def('Property', ['key', 'value']);
	var vars = def('VariableDeclaration', ['vars']);

	function vars(vars) {
		return {
			type: 'VariableDeclaration',
			declarations: Object.keys(vars).map(function (name) {
				return {
					type: 'VariableDeclarator',
					id: prop(name),
					init: vars[name]
				}
			}),
			kind: 'var'
		};
	}

	function set(left, right) {
		return {
			type: 'AssignmentExpression',
			left: left,
			operator: '=',
			right: right
		};
	}

	function call(ref) {
		return {
			type: 'CallExpression',
			callee: typeof ref === 'string' ? prop.apply(null, ref.split('.')) : ref,
			arguments: Array.prototype.slice.call(arguments, 1)
		};
	}
}

start = block:block {
	return {
		type: 'Program',
		body: [
			vars({
				$RESULT: val({}),
				$TYPES: val({})
			}),
			{
				type: 'WithStatement',
				object: prop('$RESULT'),
				body: block
			}
		]
	};
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

number = number:(hex_number / bin_number / oct_number / dec_number) { return val(number) }

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

string = '"' chars:char* '"' _ { return val(chars.join('')) }

name = prefix:[A-Za-z_] main:[A-Za-z_0-9]* _ { return prop(prefix + main.join('')) }

indexed = name:name index:("[" expr:expression? "]" { return expr }) {
	var result = prop(name, index);
	result.computed = true;
	return result;
}

ref = indexed / name

assignment = ref:ref "=" _ expr:expression { return set(ref, expr) }

struct = type:("struct" / "union") __ name:name? block:bblock {
	if (type === 'union') {
		var newBody = [vars({
			$START: call('binary.tell')
		})];

		var seekBack = {
			type: 'ExpressionStatement',
			expression: call('binary.seek', prop('$START'))
		};

		block.body.forEach(function (stmt, index) {
			if (index > 0) newBody.push(seekBack);
			newBody.push(stmt);
		});

		block.body = newBody;
	}

	block.body = [
		vars({
			$RESULT: val({})
		}),
		{
			type: 'WithStatement',
			object: prop('$RESULT'),
			body: {
				type: 'BlockStatement',
				body: block.body
			}
		},
		{
			type: 'ReturnStatement',
			argument: prop('$RESULT')
		}
	];

	var expression = call('jBinary.Type', val({
		read: {
			type: 'FunctionExpression',
			params: [],
			body: block
		}
	}));

	if (name) {
		expression = set(customTypes[name.name] = prop('$TYPES', name), expression);
	}

	return expression;
}

type = struct / prefix:(prefix:"unsigned" __ { return prefix + ' ' })? name:name {
	name = prefix + name.name;
	return customTypes[name] || {type: 'Literal', value: name};
}

expression = call / ref / string / number

args = args:(ref:ref "," _ { return ref })* last:ref? {
	if (last) args.push(last);
	return args;
}

call = ref:ref "(" _ args:args ")" _ {
	args.unshift(prop('binary'));

	return {
		type: 'CallExpression',
		callee: prop(ref, 'call'),
		arguments: args
	};
}

var_file = type:type ref:ref {
	return set(prop('$RESULT', ref.type === 'MemberExpression' ? ref.object : ref), {
		type: 'CallExpression',
		callee: prop('binary', 'read'),
		arguments: [
			ref.type === 'MemberExpression'
			? {
				type: 'ArrayExpression',
				elements: [
					val('array'),
					type,
					ref.property || prop('undefined')
				]
			}
			: type
		]
	});
}

var_local = kind:("local" / "const") __ type:type ref:(assignment / ref) {
	return {
		type: 'VariableDeclaration',
		declarations: [{
			type: 'VariableDeclarator',
			id: ref.type === 'AssignmentExpression' ? ref.left : ref,
			init: ref.right
		}],
		kind: 'var'
	};
}

var = var_local / var_file

statement = stmt:(var / struct / expression) eol {
	return /Expression$/.test(stmt.type) ? {type: 'ExpressionStatement', expression: stmt} : stmt;
}

block = stmts:statement* {
	return {
		type: 'BlockStatement',
		body: stmts
	};
}

bblock = "{" _ block:block "}" _ { return block }