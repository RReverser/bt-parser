var PEG = require('pegjs'),
	beautify = require('js-beautify').js_beautify,
	SourceNode = require('source-map').SourceNode,
	fs = require('fs'),
	util = require('util'),
	encoding = {encoding: 'utf-8'};

fs.readFile('syntax.pegjs', encoding, function (err, peg) {
	if (err) throw err;
	
	var parser = PEG.buildParser(peg, {
		trackLineAndColumn: true
	});
	
	var srcFilename = 'sample.bt',
		destFilename = srcFilename.replace(/\.bt$/, '.gen.js'),
		destMapFilename = destFilename + '.map';

	fs.readFile(srcFilename, encoding, function (err, res) {
		if (err) throw err;
		var parsed = parser.parse(res);
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
	});

	fs.writeFile('parser.gen.js', parser.toSource(), encoding);
});