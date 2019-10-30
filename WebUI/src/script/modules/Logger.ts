export function LogError(message: string): void {
	console.error(message);
}

export function Log(level: LOGLEVEL, message: string): void {
	const logLevel = LOGLEVEL.VERBOSE;

	if (level <= logLevel) {
		console.log(message);
	}
}
