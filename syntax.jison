%{
	function def(type, init, proto) {
		proto = proto || {};

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

				case 'object':
					init.forEach(function (key, i) {
						var value = args[i];
						if (value === undefined) {
							value = proto[key];
						}
						instance[key] = value;
					});
					break;
			}

			return instance;
		}

		Class.prototype = proto;
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
	}, {
		kind: 'var',
		toFileVars: function () {
			this.jb_isFile = true;
			return this;
		}
	});
	var inContext = def('WithStatement', ['object', 'body']);
	var stmt = def('ExpressionStatement', ['expression']);
	var block = def('BlockStatement', 'body');
	var ret = def('ReturnStatement', ['argument']);
	var func = def('FunctionExpression', ['params', 'body']);
	var array = def('ArrayExpression', 'elements');
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

	var jb_read = function (type) {
		return call(member(id('$BINARY'), id('read')), [type]);
	};

	var jb_type = function (name) {
		return member(id('$TYPESET'), literal(name), true);
	};

	var jb_struct = function (keyword, $block, defineId) {
		var scope = obj(),
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
			$block.body.unshift(vars({
				id: id('$UNION'),
				init: create(id('JB_UNION'), [id('$BINARY')])
			}));

			$block.body.push(stmt(call(
				member(id('$UNION'), id('done'))
			)));
		}

		$block.body.push(ret(scope));

		var expr = call(member(id('jBinary'), id('Type')), [
			obj({
				key: id('read'),
				value: func([], $block)
			})
		]);

		if (defineId) {
			expr = assign(jb_type(defineId), expr);
		}

		return expr;
	};
%}

%lex

%%
'//'.*						/* skip one-line comments */
'/*'[\s\S]*?'*/'			/* skip multi-line comments */
\s+						    /* skip whitespace */
\d+('.'\d+)?\b				return 'NUMBER';
('"'.*'"')|("'"."'")		return 'STRING';
'true'|'false'				return 'BOOL_CONST';
'if'|'else'|'do'|'while'|'return'|'local'|'struct'
|'switch'|'case'|'break'|'default'
							return yytext.toUpperCase();
'union'						return 'STRUCT';
[\w][\w\d]*					return 'IDENT';
([+\-*/%&^|]|'<<'|'>>')'='	return 'OP_ASSIGN_COMPLEX';
[*/]						return 'OP_MUL';
'++'|'--'					return 'OP_UPDATE';
[+-]						return 'OP_ADD';
'<<'|'>>'					return 'OP_SHIFT';
[<>]'='?					return 'OP_RELATION';
[!=]'='						return 'OP_EQUAL';
[!~]						return 'OP_NOT';
'&&'|'||'|[(){}:;,?&^|=]
							return yytext;
<<EOF>>						return 'EOF';

/lex

%left ';'
%nonassoc IF
%right ELSE
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
%left OP_RELATION
%left OP_SHIFT
%left OP_ADD
%left OP_MUL
%right OP_NOT
%nonassoc OP_UPDATE

%start program

%% /* language grammar */

program
	: block EOF {
		$1.type = 'Program';
		$1.body.unshift(vars({
			id: id('$TYPESET'),
			init: member(id('$BINARY'), id('typeSet'))
		}));
		return $1;
	}
	;

block
	: block stmt {
		$1.body.push($2);
	}
	| -> block()
	;

ident
	: IDENT -> id($1)
	;

literal
	: NUMBER -> literal(Number($1))
	| STRING -> literal(JSON.parse('"' + $1.slice(1, -1) + '"'))
	| BOOL_CONST -> literal(Boolean($1))
	;

bblock
	: '{' block '}' -> $2
	;

stmt
	: IF '(' e ')' stmt ELSE stmt -> cond($3, $5, $7)
	| IF '(' e ')' stmt -> cond($3, $5)
	| WHILE '(' e ')' stmt -> while_do($3, $5)
	| DO stmt WHILE '(' e ')' -> do_while($2, $5)
	| STRUCT IDENT bblock ';' -> stmt(jb_struct($1, $3, $2))
	| SWITCH '(' e ')' '{' switch_cases '}' -> switch_of($3, $6)
	| BREAK ';' -> brk()
	| bblock
	| vardef ';'
	| RETURN e ';' -> ret($2)
	| e ';' -> stmt($1)
	| ';' -> empty()
	;

switch_cases
	: switch_cases switch_case_condition ':' block {
		$1.push(switch_case($2, $4.body));
	}
	| -> []
	;

switch_case_condition
	: CASE e -> $2
	| DEFAULT -> null
	;

vardef
	: vardef_file -> vars.apply(null, $1).toFileVars()
	| vardef_local -> vars.apply(null, $1)
	;

vardef_file
	: vardef_file ',' ident {
		$1.push({id: $3, init: $1[0].init});
	}
	| IDENT ident -> [{id: $2, init: jb_read(jb_type($1))}]
	| STRUCT IDENT bblock ident -> [{id: $4, init: jb_read(jb_struct($1, $3, $2))}]
	| STRUCT bblock ident -> [{id: $3, init: jb_read(jb_struct($1, $2))}]
	;

vardef_local
	: LOCAL IDENT ident '=' e -> [{id: $3, init: $5}]
	| LOCAL IDENT ident -> [{id: $3}]
	| vardef_local ',' ident '=' e {
		$1.push({id: $3, init: $5});
	}
	| vardef_local ',' ident {
		$1.push({id: $3});
	}
	;

args
	: args ',' e {
		$1.push($3);
	}
	| e -> [$1]
	;

e
	: e OP_ADD e -> binary($1, $2, $3)
	| e OP_MUL e -> binary($1, $2, $3)
	| e OP_SHIFT e -> binary($1, $2, $3)
	| e OP_RELATION e -> binary($1, $2, $3)
	| e OP_EQUAL e -> binary($1, $2 + '=', $3)
	| e '&' e -> binary($1, $2, $3)
	| e '^' e -> binary($1, $2, $3)
	| e '|' e -> binary($1, $2, $3)
	| e '&&' e -> binary($1, $2, $3)
	| e '||' e -> binary($1, $2, $3)
	| ident OP_ASSIGN_COMPLEX e -> assign($1, $3, $2)
	| ident '=' e -> assign($1, $3)
	| OP_NOT e -> unary($1, $2)
	| OP_ADD e -> unary($1, $2)
	| OP_UPDATE ident -> update($2, $1, true)
	| ident OP_UPDATE -> update($1, $2)
	| e '?' e ':' e -> ternary($1, $3, $5)
	| '(' e ')' -> $2
	| ident '(' args ')' -> call($1, $3)
	| ident '(' ')' -> call($1)
	| ident
	| literal
	;