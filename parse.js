var PEG = require('pegjs'),
	beautify = require('js-beautify').js_beautify,
	fs = require('fs'),
	util = require('util'),
	encoding = {encoding: 'utf-8'};

fs.readFile('syntax.pegjs', encoding, function (err, peg) {
	if (err) throw err;
	var parser = PEG.buildParser(peg);
	fs.writeFile('generated_parser.js', parser.toSource(), encoding);
	fs.readFile('sample.bt', encoding, function (err, res) {
		if (err) throw err;
		var js = parser.parse(res);
		console.log(beautify(js));
	});
});