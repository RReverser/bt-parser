var PEG = require('pegjs'),
	fs = require('fs'),
	util = require('util'),
	encoding = {encoding: 'utf-8'};

fs.readFile('syntax.pegjs', encoding, function (err, peg) {
	if (err) throw err;
	var parser = PEG.buildParser(peg);
	fs.writeFile('generated_parser.js', parser.toSource(), encoding);
	fs.readFile('sample.bt', encoding, function (err, res) {
		if (err) throw err;
		try {
			var ast = parser.parse(res);
		} catch (e) {
			ast = e;
		}
		console.log(util.inspect(ast, {
			depth: null,
			colors: true
		}));
	});
});