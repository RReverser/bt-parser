var Parser = require('jison').Parser,
	fs = require('fs'),
	util = require('util'),
	escodegen = require('escodegen'),
	encoding = {encoding: 'utf-8'};

var parser = new Parser(fs.readFileSync('syntax.jison', encoding), {debug: true});

fs.writeFileSync('out/syntax.js', parser.generate(), encoding);
parser = require('./out/syntax');

var srcFilename = 'sample.bt',
	destFilename = 'out/sample',
	destAstFilename = destFilename + '.json',
	destJsFilename = destFilename + '.js',
	destMapFilename = destJsFilename + '.map';

var res = fs.readFileSync(srcFilename, encoding);
var parsed = parser.parse(res);

console.log(parsed);

fs.writeFileSync(destAstFilename, JSON.stringify(parsed, null, '\t'), encoding)

var generated = escodegen.generate(parsed, {
	sourceMap: srcFilename,
	sourceMapWithCode: true
});

fs.writeFile(destJsFilename, generated.code + '\n//# sourceMappingURL=sample.js.map', encoding);
fs.writeFile(destMapFilename, generated.map, encoding);
fs.writeFile('out/' + srcFilename, res, encoding);