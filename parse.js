var PEG = require('pegjs'),
	SourceNode = require('source-map').SourceNode,
	fs = require('fs'),
	util = require('util'),
	escodegen = require('escodegen'),
	encoding = {encoding: 'utf-8'};

fs.readFile('syntax.pegjs', encoding, function (err, peg) {
	if (err) throw err;
	
	try {
		var parser = PEG.buildParser(peg, {
			trackLineAndColumn: true
		});
	} catch (err) {
		return console.error(err);
	}
	
	var srcFilename = 'sample.bt',
		destFilename = srcFilename.replace(/\.bt$/, '.gen'),
		destAstFilename = destFilename + '.json',
		destJsFilename = destFilename + '.js',
		destMapFilename = destJsFilename + '.map';

	fs.readFile(srcFilename, encoding, function (err, res) {
		if (err) throw err;

		try {
			var parsed = parser.parse(res);
		} catch (err) {
			return console.error(err);
		}

		fs.writeFile(destAstFilename, JSON.stringify(parsed, null, 2), encoding, function () {
			try {
				var generated = escodegen.generate(parsed, {
					sourceMap: srcFilename,
					sourceMapWithCode: true
				});
			} catch (err) {
				return console.error(err);
			}

			fs.writeFile(destJsFilename, generated.code + '\n//# sourceMappingURL=' + destMapFilename, encoding);
			fs.writeFile(destMapFilename, generated.map, encoding);
		});
	});
});