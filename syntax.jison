%{
	function def(type, init, proto) {
		proto = proto || {};

		function Class() {
			var instance = Object.create(Class.prototype),
				args = Array.prototype.slice.call(arguments),
				init = instance.__init__;

			if (init instanceof Function) {
				init.apply(instance, args);
			} else
			if (init instanceof Array) {
				init.forEach(function (key, i) {
					var value = args[i];
					if (value === undefined) {
						value = proto[key];
						if (value !== null && typeof value === 'object') {
							value = value instanceof Array ? value.slice() : Object.create(value);
						}
					}
					instance[key] = value;
				});
			}

			return instance;
		}

		Class.prototype = proto;
		Class.prototype.type = type;
		Class.prototype.constructor = Class;
		Object.defineProperty(Class.prototype, '__init__', {value: init});
		Class.prototype.at = function (jisonLoc) {
			this.loc = {
				source: 'sample.bt',
				start: {
					line: jisonLoc.first_line,
					column: jisonLoc.first_column
				},
				end: {
					line: jisonLoc.last_line,
					column: jisonLoc.last_column
				}
			};
			return this;
		};
		Class.prototype.toString = function () { return '[' + this.type + ']' };
		Class.prototype.toJSON = function () {
			var tmp = {};
			
			[Class.prototype, this]
			.forEach(function (obj) {
				for (var name in obj) {
					if (obj.hasOwnProperty(name)) {
						tmp[name] = obj[name];
					}
				}
			});

			return tmp;
		};

		return Class;
	}

	var program = def('Program', ['body']);
	var id = def('Identifier', ['name']);
	var member = def('MemberExpression', ['object', 'property', 'computed'], {computed: false});
	var literal = def('Literal', ['value']);
	var obj = def('ObjectExpression', function (properties) {
		this.properties = properties.map(function (property) {
			property.type = 'Property';
			return property /* key, value */;
		});
	});
	var assign = def('AssignmentExpression', ['left', 'right', 'operator'], {operator: '='});
	var update = def('UpdateExpression', ['argument', 'operator', 'prefix']);
	var call = def('CallExpression', ['callee', 'arguments'], {
		arguments: []
	});
	var create = def('NewExpression', ['callee', 'arguments'], {
		arguments: []
	});
	var vars = def('VariableDeclaration', function (declarations) {
		this.declarations = declarations.map(function (declaration) {
			declaration.type = 'VariableDeclarator';
			return declaration /* id, init */;
		});
	}, {
		kind: 'var',
		toFileVars: function () {
			this.jb_isFile = true;
			this.declarations.forEach(function (declaration) {
				declaration.init = call(id('JB_DECLARE'), [declaration.id, declaration.init]);
			});
			return this;
		}
	});
	var stmt = def('ExpressionStatement', ['expression']);
	var block = def('BlockStatement', ['body']);
	var ret = def('ReturnStatement', ['argument']);
	var func = def('FunctionExpression', ['params', 'body']);
	var funcdef = def('FunctionDeclaration', ['id', 'params', 'body']);
	var array = def('ArrayExpression', ['elements'], {
		elements: []
	});
	var binary = def('BinaryExpression', ['left', 'operator', 'right']);
	var unary = def('UnaryExpression', ['operator', 'argument'], {prefix: true});
	var ternary = def('ConditionalExpression', ['test', 'consequent', 'alternate']);
	var cond = def('IfStatement', ['test', 'consequent', 'alternate']);
	var while_do = def('WhileStatement', ['test', 'body']);
	var do_while = def('DoWhileStatement', ['body', 'test']);
	var empty = def('EmptyStatement');
	var brk = def('BreakStatement', ['label']);
	var switch_case = def('SwitchCase', ['test', 'consequent'], {
		consequent: []
	});
	var switch_of = def('SwitchStatement', ['discriminant', 'cases'], {
		cases: []
	});
	var for_cond = def('ForStatement', ['init', 'test', 'update', 'body']);
	var self = def('ThisExpression');

	var jb_read = function (type) {
		return call(member(id('$BINARY'), id('read')), [type]);
	};

	var jb_type = function (name) {
		return member(id('$TYPESET'), literal(name), true);
	};

	var jb_struct = function (keyword, $block, defineId, args) {
		var scope = obj([]),
			isUnion = keyword === 'union';

		(function traverse(node) {
			if (node.type === 'VariableDeclaration') {
				if (node.jb_isFile) {
					node.declarations.forEach(function (declaration) {
						var name = declaration.id;

						scope.properties.push({
							key: name,
							value: name
						});

						if (isUnion) {
							declaration.init.callee.object = id('$UNION');
						}
					});
				}
			} else {
				for (var name in node) {
					var subNode = node[name];
					if (typeof subNode === 'object') {
						traverse(subNode);
					}
				}
			}
		})($block);

		if (isUnion) {
			$block.body.unshift(vars([{
				id: id('$UNION'),
				init: create(id('JB_UNION'), [id('$BINARY')])
			}]));

			$block.body.push(stmt(call(
				member(id('$UNION'), id('done'))
			)));
		}

		$block.body.push(ret(scope));

		var props = [{
			key: id('read'),
			value: func([], $block)
		}];

		if (args) {
			props.unshift({
				key: id('params'),
				value: array(args.map(function (arg) {
					return literal(arg.name);
				}))
			});

			$block.body.unshift(vars(args.map(function (arg) {
				return {
					id: arg,
					init: member(self(), arg)
				};
			})));
		}

		var expr = call(member(id('jBinary'), id('Type')), [obj(props)]);

		if (defineId) {
			expr = assign(jb_type(defineId), expr);
		}

		return expr;
	};

	var jb_fitType = function (declaration, type) {
		if ('jb_bits' in declaration) {
			type = declaration.jb_bits;
		} else {
			if ('jb_args' in declaration) {
				type = array([type].concat(declaration.jb_args));
			}

			if (declaration.jb_count !== undefined) {
				type = array([
					literal('array'),
					type,
					declaration.jb_count
				]);
			}
		}

		return type;
	};

	var jb_valueOf = function (e) {
		return e && e.type === 'Identifier' ? call(id('JB_VALUEOF'), [e]) : e;
	};
%}

%lex

%%
'//'.*						/* skip one-line comments */
'/*'[\s\S]*?'*/'			/* skip multi-line comments */
\s+						    /* skip whitespace */
'0x'[A-Fa-f0-9]+			return 'NUMBER';
\d+('.'\d+)?				return 'NUMBER';
('"'.*'"')|("'"."'")		return 'STRING';
('true'|'false')\b			return 'BOOL_CONST';
('if'|'else'|'do'|'while'|'return'|'local'|'struct'
|'switch'|'case'|'break'|'default'|'for'|'typedef'|'enum')\b
							return yytext.toUpperCase();
'const'						return 'LOCAL';
'union'						return 'STRUCT';
[A-Za-z_][\w]*				return 'IDENT';
([+\-*/%&^|]|'<<'|'>>')'='	return 'OP_ASSIGN_COMPLEX';
[*/]						return 'OP_MUL';
'++'|'--'					return 'OP_UPDATE';
[+-]						return 'OP_ADD';
'<<'|'>>'					return 'OP_SHIFT';
[<>]'='						return 'OP_RELATION';
[!=]'='						return 'OP_EQUAL';
'!'							return 'OP_NOT';
'~'							return 'OP_INVERSE';
'&&'|'||'|[<>(){}\[\]:;,?&^|=\.]
							return yytext;
<<EOF>>						return 'EOF';

/lex

%left ';'
%nonassoc IF
%right ELSE
%left ','
%right OP_ASSIGN_COMPLEX
%right '='
%right ':'
%right '?'
%left '||'
%left '&&'
%left '|'
%left '^'
%left '&'
%left OP_EQUAL
%left '<'
%left '>'
%left OP_RELATION
%left OP_SHIFT
%left OP_ADD
%left OP_MUL
%right OP_NOT
%nonassoc OP_UPDATE

%start program

%ebnf

%% /* language grammar */

program
	: block EOF {
		$block.type = 'Program';
		return $block;
	}
	;

block
	: stmt*[stmts] -> block($stmts)
	;

bblock
	: '{' block '}' -> $block
	;

ident
	: IDENT -> id($IDENT)
	;

member
	: member '.' ident -> member($member, $ident)
	| member index -> member($member, $index, true)
	| ident
	;

literal
	: NUMBER -> literal(Number($NUMBER))
	| string
	| BOOL_CONST -> literal(Boolean($BOOL_CONST))
	;

string
	: STRING -> literal(JSON.parse('"' + $STRING.slice(1, -1) + '"'))
	;

struct
	: STRUCT IDENT?[struct_name] argdefs?[struct_args] bblock -> jb_struct($STRUCT, $bblock, $struct_name, $struct_args)
	;

enum_type
	: ENUM enum_basetype IDENT?[enum_name] '{' enum_items '}' {
		$$ = array([
			literal('enum'),
			literal($enum_basetype),
			call(id('JB_ENUM'), [obj($enum_items)])
		]);

		if ($enum_name) {
			$$ = assign(jb_type($enum_name), $$);
		}
	}
	;

enum_basetype
	: '<' IDENT '>' -> $IDENT
	| -> 'int'
	;

enum_items
	: enum_items ',' enum_item {
		$enum_items.push($enum_item);
	}
	| enum_item -> [$enum_item]
	;

enum_item
	: ident '=' e -> {key: $ident, value: $e}
	| ident -> {key: $ident, value: id('undefined')}
	;

stmt
	: IF '(' e ')' stmt ELSE stmt -> cond(jb_valueOf($e), $stmt1, $stmt2)
	| IF '(' e ')' stmt -> cond(jb_valueOf($e), $stmt)
	| WHILE '(' e ')' stmt -> while_do(jb_valueOf($e), $stmt)
	| DO stmt WHILE '(' e ')' -> do_while($stmt, jb_valueOf($e))
	| FOR '(' e ';' e ';' e ')' stmt -> for_cond($e1, jb_valueOf($e2), $e3, $stmt)
	| struct ';' -> stmt($struct)
	| TYPEDEF vardef_file ';' {
		var firstItem = $vardef_file.items[0];

		$$ = stmt(assign(
			jb_type(firstItem.id.name),
			jb_fitType(firstItem, $vardef_file.type)
		));
	}
	| SWITCH '(' e ')' '{' switch_case*[cases] '}' -> switch_of($e, $cases)
	| BREAK ';' -> brk()
	| IDENT ident argdefs bblock -> funcdef($ident, $argdefs, $bblock)
	| bblock
	| vardef ';'
	| RETURN e ';' -> ret($e)
	| e ';' -> stmt($e)
	| ';' -> empty()
	;

argdefs
	: '(' argdef_items ')' -> $argdef_items
	| '(' ')' -> []
	;

argdef_items
	: argdef_items ',' argdef {
		$$.push($argdef);
	}
	| argdef -> [$argdef]
	;

argdef
	: IDENT ident -> $ident
	;

switch_case
	: switch_condition ':' block -> switch_case($switch_condition, $block.body)
	;

switch_condition
	: CASE e -> $e
	| DEFAULT -> null
	;

index
	: '[' e ']' -> $e
	;

vardef
	: vardef_file {
		$vardef_file.items.forEach(function (declaration) {
			declaration.init = jb_read(jb_fitType(
				declaration,
				$vardef_file.type
			));
		});
		$$ = vars($vardef_file.items).toFileVars();
	}
	| vardef_local -> vars($vardef_local)
	;

vardef_file
	: IDENT vardef_file_items -> {items: $vardef_file_items, type: literal($IDENT)}
	| struct vardef_file_items -> {items: $vardef_file_items, type: $struct}
	| enum_type vardef_file_items -> {items: $vardef_file_items, type: $enum_type}
	;

vardef_file_items
	: vardef_file_items ',' vardef_file_item {
		$$.push($vardef_file_item);
	}
	| vardef_file_item -> [$vardef_file_item]
	;

vardef_file_item
	: ident '(' arg_items ')' index?[jb_count] -> {id: $ident, jb_count: $jb_count, jb_args: $arg_items}
	| ident index?[jb_count] -> {id: $ident, jb_count: $jb_count}
	| ident ':' e -> {id: $ident, jb_bits: $e}
	;

vardef_local
	: LOCAL IDENT vardef_local_items -> $vardef_local_items
	;

vardef_local_items
	: vardef_local_items ',' vardef_local_item {
		$$.push($vardef_local_item);
	}
	| vardef_local_item -> [$vardef_local_item]
	;

vardef_local_item
	: ident '=' e -> {id: $ident, init: $e}
	| ident index '=' '{' arg_items?[args_opt] '}' -> {id: $ident, init: call(member(array($args_opt), id('concat')), [create(id('Array'), [binary($index, '-', literal(($args_opt || []).length))])])}
	| ident index '=' string -> {id: $ident, init: binary($string, '+', call(member(create(id('Array'), [binary($index, '-', literal($string.value.length - 1))]), id('join')), [literal('\0')]))}
	| ident index -> {id: $ident, init: create(id('Array'), [$index])}
	| ident -> {id: $ident}
	;

arg_items
	: arg_items ',' e {
		$$.push($e);
	}
	| e -> [$e]
	;

e
	: e OP_ADD e -> binary($1, $2, $3)
	| e OP_MUL e -> binary($1, $2, $3)
	| e OP_SHIFT e -> binary($1, $2, $3)
	| e '<' e -> binary($1, $2, $3)
	| e '>' e -> binary($1, $2, $3)
	| e OP_RELATION e -> binary($1, $2, $3)
	| e OP_EQUAL e -> binary($1, $2, $3)
	| e '&' e -> binary($1, $2, $3)
	| e '^' e -> binary($1, $2, $3)
	| e '|' e -> binary($1, $2, $3)
	| e '&&' e -> binary(jb_valueOf($1), $2, jb_valueOf($3))
	| e '||' e -> binary(jb_valueOf($1), $2, jb_valueOf($3))
	| member OP_ASSIGN_COMPLEX e -> assign($member, $e, $OP_ASSIGN_COMPLEX)
	| member '=' e {
		if ($member.computed) {
			$e = call(id('JB_ASSIGN_MEMBER'), [$member.object, $member.property, $e]);
			$member = $member.object;
		}

		$$ = assign($member, $e);
	}
	| OP_NOT e -> unary($OP_NOT, jb_valueOf($e))
	| OP_INVERSE e -> unary($OP_INVERSE, $e)
	| OP_ADD e -> unary($OP_ADD, $e)
	| OP_UPDATE member -> update($member, $OP_UPDATE, true)
	| member OP_UPDATE -> update($member, $OP_UPDATE)
	| e '?' e ':' e -> ternary(jb_valueOf($e1), $e2, $e3)
	| '(' e ')' -> $e
	| ident '(' arg_items?[args_opt] ')' -> call($ident, $args_opt)
	| member
	| literal
	;