function LittleEndian() {}
function ReadByte() {}

var $BINARY = new jBinary(1024, {
	uint: 'uint32'
});

function JB_UNION(binary) {
	this.binary = binary;
	this.begin = this.end = binary.tell();
}

JB_UNION.prototype.read = function () {
	var result = this.binary.apply(this.binary, arguments);
	this.end = Math.max(this.end, this.binary.tell());
	this.seek(this.begin);
	return result;
};

JB_UNION.prototype.done = function () {
	this.seek(this.end);
};