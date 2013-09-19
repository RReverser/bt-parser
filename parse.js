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
		destFilename = srcFilename.replace(/\.bt$/, '.gen.js'),
		destMapFilename = destFilename + '.map';

	fs.readFile(srcFilename, encoding, function (err, res) {
		if (err) throw err;
		var parsed = parser.parse(res);
		fs.writeFile(destFilename + 'on', JSON.stringify(parsed, null, 2), encoding, function () {
			fs.writeFile(destFilename, escodegen.generate(parsed), encoding);
		});
		/*
		var node = new SourceNode(null, null, null, '');
		node.add(fs.readFileSync('wrapper_begin.js', encoding));
		node.add((function mapper(stmt) {
			return new SourceNode(stmt.line, stmt.column, srcFilename, stmt instanceof Array ? stmt.map(mapper) : stmt.toString());
		})(parsed));
		node.add(fs.readFileSync('wrapper_end.js', encoding));
		var output = node.toStringWithSourceMap({
			file: destMapFilename
		});
		fs.writeFile(destFilename, output.code + '\n//# sourceMappingURL=' + destMapFilename, encoding);
		fs.writeFile(destMapFilename, output.map, encoding);
		*/
	});
});