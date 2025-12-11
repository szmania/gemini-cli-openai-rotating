export const hashString = (input: string): number => {
	let hash = 0;
	for (let i = 0; i < input.length; i++) {
		const chr = input.charCodeAt(i);
		hash = (hash << 5) - hash + chr;
		hash |= 0;
	}
	return Math.abs(hash);
};
