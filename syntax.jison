%{
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

				case 'object':
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
	var ternary = def('ConditionalExpression', ['test', 'consequent', 'alternate']);
	var cond = def('IfStatement', ['test', 'consequent', 'alternate']);
	var while_do = def('WhileStatement', ['test', 'body']);
	var do_while = def('DoWhileStatement', ['body', 'test']);
	var empty = def('EmptyStatement');
%}

%lex

%%
\s+						/* skip whitespace */
[\d]+('.'[\d]+)?\b			return 'NUMBER';
('true'|'false')			return 'BOOL_CONST';
('if'|'else'|'do'|'while')	return 'OP_' + yytext.toUpperCase();
[\w][\w\d]*					return 'IDENT';
'++'|'--'					return 'OP_UPDATE';
[*/]						return 'OP_MUL';
[+-]						return 'OP_ADD';
'<<'|'>>'					return 'OP_SHIFT';
[<>]'='?					return 'OP_RELATION';
[!=]'='						return 'OP_EQUAL';
'&'							return 'OP_BIT_AND';
'^'							return 'OP_BIT_XOR';
'|'							return 'OP_BIT_OR';
'&&'						return 'OP_LOGIC_AND';
'||'						return 'OP_LOGIC_OR';
'?'							return 'OP_TERNARY';
':'							return 'OP_COLON';
';'							return 'OP_SEMICOLON';
[!~]						return 'OP_NOT';
([+\-*/%&^|]|'<<'|'>>')?'='	return 'OP_ASSIGN';
[(){}]						return yytext;
<<EOF>>						return 'EOF';

/lex

%left OP_SEMICOLON
%nonassoc OP_IF
%right OP_ELSE
%right OP_ASSIGN
%right OP_COLON
%right OP_TERNARY
%left OP_LOGIC_OR
%left OP_LOGIC_AND
%left OP_BIT_OR
%left OP_BIT_XOR
%left OP_BIT_AND
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
		return $1;
	}
	| EOF -> program()
	;

block
	: block stmt {
		($$ = $1).body.push($2);
	}
	| stmt -> block($1)
	;

type
	: IDENT -> literal($1)
	;

ident
	: IDENT -> id($1)
	;

literal
	: NUMBER -> literal(Number($1))
	| BOOL_CONST -> literal(Boolean($1))
	;

bblock
	: '{' block '}' -> $2
	| '{' '}' -> block()
	;

stmt
	/* : type ident OP_SEMICOLON -> vars({id: $2, init: call(member(id('$BINARY', 'read')), [$1])}) */
	: OP_IF '(' e ')' stmt OP_ELSE stmt -> cond($3, $5, $7)
	| OP_IF '(' e ')' stmt -> cond($3, $5)
	| OP_WHILE '(' e ')' stmt -> while_do($3, $5)
	| OP_DO stmt OP_WHILE '(' e ')' -> do_while($2, $5)
	| bblock
	| e OP_SEMICOLON -> stmt($1)
	| OP_SEMICOLON -> empty()
	;

e
	: e OP_ADD e -> binary($1, $2, $3)
	| e OP_MUL e -> binary($1, $2, $3)
	| e OP_SHIFT e -> binary($1, $2, $3)
	| e OP_RELATION e -> binary($1, $2, $3)
	| e OP_EQUAL e -> binary($1, $2, $3)
	| e OP_BIT_AND e -> binary($1, $2, $3)
	| e OP_BIT_XOR e -> binary($1, $2, $3)
	| e OP_BIT_OR e -> binary($1, $2, $3)
	| e OP_LOGIC_AND e -> binary($1, $2, $3)
	| e OP_LOGIC_OR e -> binary($1, $2, $3)
	| ident OP_ASSIGN e -> assign($1, $3, $2)
	| OP_NOT e -> unary($1, $2)
	| OP_ADD e -> unary($1, $2)
	| OP_UPDATE ident -> update($2, $1, true)
	| ident OP_UPDATE -> update($1, $2)
	| e OP_TERNARY e OP_COLON e -> ternary($1, $3, $5)
	| '(' e ')' -> $2
	| ident
	| literal
	;