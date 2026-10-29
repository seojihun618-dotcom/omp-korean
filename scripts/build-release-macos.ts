#!/usr/bin/env bun
import { createHash } from "node:crypto";
import * as fs from "node:fs/promises";
import * as path from "node:path";

const root = path.resolve(import.meta.dir, "..");
const installerMarker = "DEFAULT_REPOSITORY='seojihun618-dotcom/omp-korean' # RELEASE_REPOSITORY";
const repositoryPattern = /^[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*$/;
let repository = process.env.GITHUB_REPOSITORY || "seojihun618-dotcom/omp-korean";
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
	if (args[i] !== "--repository" || !args[i + 1] || args[i + 1].startsWith("--")) {
		throw new Error("Usage: bun scripts/build-release-macos.ts [--repository owner/name]");
	}
	repository = args[++i];
}
if (!repositoryPattern.test(repository)) throw new Error("Repository must be a GitHub owner/name.");
if (process.platform !== "darwin" || (process.arch !== "arm64" && process.arch !== "x64")) {
	throw new Error("Build natively on macOS arm64 or x64 using the matching Bun architecture.");
}

async function command(
	argv: string[],
	cwd = root,
	env: NodeJS.ProcessEnv = process.env,
	capture = false,
): Promise<{ stdout: string; stderr: string }> {
	const child = Bun.spawn(argv, {
		cwd,
		env,
		stdin: "ignore",
		stdout: capture ? "pipe" : "inherit",
		stderr: capture ? "pipe" : "inherit",
	});
	const [code, stdout, stderr] = await Promise.all([
		child.exited,
		capture ? new Response(child.stdout as ReadableStream).text() : Promise.resolve(""),
		capture ? new Response(child.stderr as ReadableStream).text() : Promise.resolve(""),
	]);
	if (code !== 0) throw new Error(`Command failed (${code}): ${argv.join(" ")}\n${stderr}`);
	return { stdout, stderr };
}

async function json(file: string): Promise<Record<string, unknown>> {
	const value: unknown = await Bun.file(file).json();
	if (typeof value !== "object" || value === null || Array.isArray(value)) {
		throw new Error(`Expected a JSON object: ${file}`);
	}
	return value as Record<string, unknown>;
}

const pins = await json(path.join(root, "release.json"));
if (
	typeof pins.version !== "string" || !/^\d+\.\d+\.\d+-ko\.\d+$/.test(pins.version) ||
	typeof pins.upstreamVersion !== "string" || pins.version.split("-ko.")[0] !== pins.upstreamVersion ||
	typeof pins.upstreamCommit !== "string" || !/^[0-9a-f]{40}$/.test(pins.upstreamCommit) ||
	typeof pins.bunVersion !== "string" || !/^\d+\.\d+\.\d+$/.test(pins.bunVersion) ||
	pins.platform !== "windows-x64" || pins.archive !== `omp-korean-${pins.version}-windows-x64.zip`
) throw new Error("Invalid pinned Windows release manifest.");
const bunVersion = (await command([process.execPath, "--version"], root, process.env, true)).stdout.trim();
if (bunVersion !== pins.bunVersion) throw new Error(`Bun ${pins.bunVersion} required; found ${bunVersion}.`);
const hardware = (await command(["/usr/bin/uname", "-m"], root, process.env, true)).stdout.trim();
if (hardware !== (process.arch === "arm64" ? "arm64" : "x86_64")) {
	throw new Error("Bun architecture must match the native macOS host.");
}
// uname can report x86_64 under Rosetta; translated Intel builds are not native builds.
const translated = Bun.spawn(["/usr/sbin/sysctl", "-in", "sysctl.proc_translated"], {
	stdin: "ignore", stdout: "pipe", stderr: "ignore",
});
const [translationStatus, translationValue] = await Promise.all([
	translated.exited, new Response(translated.stdout).text(),
]);
if (translationStatus === 0 && translationValue.trim() === "1") throw new Error("Rosetta builds are not supported.");

const manifest = {
	version: pins.version,
	upstreamVersion: pins.upstreamVersion,
	upstreamCommit: pins.upstreamCommit,
	bunVersion: pins.bunVersion,
	platform: `macos-${process.arch}`,
	archive: `omp-korean-${pins.version}-macos-${process.arch}.tar.gz`,
};
for (const relative of [
	"source/omp-language-pack.patch", "locales/ko.json", "locales/en.json", "LICENSE",
	"THIRD-PARTY-NOTICES.txt", "README.md", "install.sh",
]) {
	if (!(await fs.stat(path.join(root, relative))).isFile()) throw new Error(`Missing release input: ${relative}`);
}
for (const locale of ["ko", "en"]) {
	const catalog = await json(path.join(root, `locales/${locale}.json`));
	if (Object.values(catalog).some(value => typeof value !== "string")) throw new Error(`Invalid ${locale} catalog.`);
}
let installer = await Bun.file(path.join(root, "install.sh")).text();
if (installer.split(installerMarker).length !== 2) throw new Error("Installer repository stamp marker is missing or ambiguous.");
installer = installer.replace(installerMarker, `DEFAULT_REPOSITORY='${repository}' # RELEASE_REPOSITORY`);
await fs.mkdir(path.join(root, "build"), { recursive: true });
const work = await fs.mkdtemp(path.join(root, `build/macos-${process.arch}-`));
const source = path.join(work, "source");
const stage = path.join(work, "package");
const output = path.join(root, "release");
await fs.mkdir(stage);
await fs.mkdir(output, { recursive: true });
await command(["git", "init", "--quiet", source]);
await command(["git", "-C", source, "remote", "add", "origin", "https://github.com/can1357/oh-my-pi.git"]);
await command(["git", "-C", source, "fetch", "--depth=1", "origin", manifest.upstreamCommit]);
await command(["git", "-C", source, "-c", "core.autocrlf=false", "checkout", "--detach", "FETCH_HEAD"]);
if ((await command(["git", "-C", source, "rev-parse", "HEAD"], root, process.env, true)).stdout.trim() !== manifest.upstreamCommit) {
	throw new Error("Reconstructed upstream commit mismatch.");
}
await command(["git", "-C", source, "apply", "--binary", "--whitespace=nowarn", path.join(root, "source/omp-language-pack.patch")]);
const sourceLocales = path.join(source, "packages/utils/src/locales");
await fs.mkdir(sourceLocales, { recursive: true });
for (const locale of ["ko", "en"]) await fs.copyFile(path.join(root, `locales/${locale}.json`), path.join(sourceLocales, `${locale}.json`));
await command([process.execPath, "install", "--frozen-lockfile", "--ignore-scripts"], source);

// Download the exact official native addon without executing npm lifecycle scripts.
const packageName = `@oh-my-pi/pi-natives-darwin-${process.arch}`;
const nativeManifest = await json(path.join(source, "packages/natives/package.json"));
if (nativeManifest.version !== manifest.upstreamVersion) throw new Error("Reconstructed native package version mismatch.");
async function download(url: string): Promise<Response> {
	const response = await fetch(url, { signal: AbortSignal.timeout(120_000), redirect: "error" });
	if (!response.ok) throw new Error(`Download failed (${response.status}): ${url}`);
	return response;
}
const metadata: unknown = await (await download(`https://registry.npmjs.org/${encodeURIComponent(packageName)}/${manifest.upstreamVersion}`)).json();
if (typeof metadata !== "object" || metadata === null) throw new Error("Invalid native package metadata.");
const published = metadata as { name?: unknown; version?: unknown; dist?: { tarball?: unknown; integrity?: unknown } };
if (
	published.name !== packageName || published.version !== manifest.upstreamVersion ||
	typeof published.dist?.tarball !== "string" || typeof published.dist.integrity !== "string" ||
	!/^sha512-[A-Za-z0-9+/]{86}==$/.test(published.dist.integrity)
) throw new Error("Invalid exact-version native package metadata.");
const tarballUrl = new URL(published.dist.tarball);
if (tarballUrl.protocol !== "https:" || tarballUrl.hostname !== "registry.npmjs.org" || tarballUrl.port || tarballUrl.username || tarballUrl.password) {
	throw new Error("Native tarball must come from HTTPS registry.npmjs.org.");
}
const nativeArchive = path.join(work, "native.tgz");
await Bun.write(nativeArchive, await download(tarballUrl.href));
async function digest(file: string, algorithm: string, encoding: "hex" | "base64"): Promise<string> {
	const hash = createHash(algorithm);
	for await (const chunk of Bun.file(file).stream()) hash.update(chunk);
	return hash.digest(encoding);
}
if (`sha512-${await digest(nativeArchive, "sha512", "base64")}` !== published.dist.integrity) throw new Error("Native package SHA-512 integrity mismatch.");
const memberText = (await command(["/usr/bin/tar", "-tf", nativeArchive], root, process.env, true)).stdout;
const members = memberText.trimEnd().split("\n");
const seen = new Set<string>();
for (const member of members) {
	if (!/^package\/[A-Za-z0-9._/-]+$/.test(member) || /(^|\/)\.\.?(\/|$)/.test(member) || seen.has(member)) {
		throw new Error(`Unsafe or duplicate native archive member: ${member}`);
	}
	seen.add(member);
}
async function exportMember(member: string, destination: string): Promise<void> {
	if (!seen.has(member)) throw new Error(`Native archive lacks ${member}.`);
	// Never extract archive paths or links: stream one literal member into our chosen path.
	const child = Bun.spawn(["/usr/bin/tar", "-xOf", nativeArchive, member], { stdin: "ignore", stdout: "pipe", stderr: "pipe" });
	const [code, , stderr] = await Promise.all([
		child.exited, Bun.write(destination, new Response(child.stdout)), new Response(child.stderr).text(),
	]);
	if (code !== 0 || (await fs.stat(destination)).size === 0) throw new Error(`Cannot read native member ${member}: ${stderr}`);
}
const nativePackageJson = path.join(work, "native-package.json");
await exportMember("package/package.json", nativePackageJson);
const nativePackage = await json(nativePackageJson);
if (nativePackage.name !== packageName || nativePackage.version !== manifest.upstreamVersion) throw new Error("Native archive package identity mismatch.");
const nativeDir = path.join(source, "packages/natives/native");
await fs.mkdir(nativeDir, { recursive: true });
const nativeNames = process.arch === "arm64"
	? ["pi_natives.darwin-arm64.node"]
	: ["pi_natives.darwin-x64-baseline.node", "pi_natives.darwin-x64-modern.node"];
for (const name of nativeNames) {
	if (name.endsWith("-modern.node") && !seen.has(`package/${name}`)) continue;
	await exportMember(`package/${name}`, path.join(nativeDir, name));
}
await command([process.execPath, "scripts/build-localized.ts"], source);
const kit = path.join(stage, "update");
await fs.mkdir(path.join(kit, "scripts"), { recursive: true });
await fs.mkdir(path.join(kit, "locales"));
await command([process.execPath, "scripts/reapply-localization.ts", "create", "--source", source, "--base", manifest.upstreamCommit, "--output", path.join(kit, "reference.json")], source);
await command([process.execPath, "build", "scripts/update-localized.ts", "--target=bun", "--outfile", path.join(kit, "update-localized.js")], source);
await fs.copyFile(process.execPath, path.join(kit, "bun"));
for (const name of ["update-localized.ts", "reapply-localization.ts", "build-localized.ts"]) {
	await fs.copyFile(path.join(source, `scripts/${name}`), path.join(kit, `scripts/${name}`));
}
await fs.copyFile(path.join(source, "packages/coding-agent/src/cli/localized-update.ts"), path.join(kit, "scripts/localized-update.ts"));
await fs.mkdir(path.join(stage, "locales"));
for (const locale of ["ko", "en"]) {
	await fs.copyFile(path.join(root, `locales/${locale}.json`), path.join(stage, `locales/${locale}.json`));
	await fs.copyFile(path.join(root, `locales/${locale}.json`), path.join(kit, `locales/${locale}.json`));
}
for (const relative of ["LICENSE", "THIRD-PARTY-NOTICES.txt", "README.md"]) await fs.copyFile(path.join(root, relative), path.join(stage, relative));
await fs.copyFile(path.join(source, `packages/coding-agent/binaries/omp-darwin-${process.arch}`), path.join(stage, "omp"));
const packageFiles = [
	"omp", "locales/ko.json", "locales/en.json", "LICENSE", "THIRD-PARTY-NOTICES.txt", "README.md",
	"update/bun", "update/update-localized.js", "update/reference.json", "update/scripts/update-localized.ts",
	"update/scripts/reapply-localization.ts", "update/scripts/build-localized.ts", "update/scripts/localized-update.ts",
	"update/locales/ko.json", "update/locales/en.json",
];
for (const relative of packageFiles) {
	const file = path.join(stage, relative);
	if (!(await fs.lstat(file)).isFile()) throw new Error(`Package input is not a regular file: ${relative}`);
	await fs.chmod(file, relative === "omp" || relative === "update/bun" ? 0o755 : 0o644);
}

// Run the packaged executable, not source code, with no access to the user's OMP data.
const home = path.join(work, "smoke-home");
await fs.mkdir(home);
const smokeEnv: NodeJS.ProcessEnv = {
	...process.env, HOME: home, XDG_CONFIG_HOME: path.join(home, "config"), XDG_DATA_HOME: path.join(home, "data"),
	XDG_CACHE_HOME: path.join(home, "cache"),
};
delete smokeEnv.PI_PROFILE;
delete smokeEnv.OMP_LOCALE_DIR;
const binary = path.join(stage, "omp");
for (const locale of ["en", "ko"]) {
	const env = { ...smokeEnv, OMP_LANG: locale, PI_CODING_AGENT_DIR: path.join(work, `smoke-${locale}`) };
	const reported = (await command([binary, "--version"], work, env, true)).stdout.trim();
	if (reported !== `omp/${manifest.upstreamVersion}`) throw new Error(`Binary version mismatch: ${reported}`);
	const help = (await command([binary, "--help"], work, env, true)).stdout;
	if (help.length < 100 || !help.includes("--model")) throw new Error(`Incomplete ${locale} help.`);
	const catalog = await json(path.join(stage, `locales/${locale}.json`));
	if (typeof catalog.USAGE !== "string" || !help.includes(catalog.USAGE)) {
		throw new Error(`Packaged ${locale} help did not use the shipped catalog.`);
	}
	const smoke = await command([binary, "--smoke-test"], work, env, true);
	if (!`${smoke.stdout}\n${smoke.stderr}`.includes("smoke-test: ok")) throw new Error(`Binary ${locale} smoke did not complete.`);
}
const probe = path.join(work, "probe-locales");
await fs.mkdir(probe);
await Bun.write(path.join(probe, "ko.json"), '{"USAGE":"RELEASE_LANGUAGE_PACK_PROBE"}\n');
const probeEnv = { ...smokeEnv, OMP_LOCALE_DIR: probe, PI_CODING_AGENT_DIR: path.join(work, "smoke-probe") };
const english = (await command([binary, "--help"], work, { ...probeEnv, OMP_LANG: "en" }, true)).stdout;
const korean = (await command([binary, "--help"], work, { ...probeEnv, OMP_LANG: "ko" }, true)).stdout;
if (!english.includes("USAGE") || english.includes("RELEASE_LANGUAGE_PACK_PROBE") || !korean.includes("RELEASE_LANGUAGE_PACK_PROBE") || !korean.includes("--model")) {
	throw new Error("Binary did not honor the external language pack or missing-message English fallback.");
}
const missing = path.join(work, "missing-locales");
const malformed = path.join(work, "malformed-locales");
await fs.mkdir(malformed);
await Bun.write(path.join(malformed, "ko.json"), '{"PRIVATE_RELEASE_PACK_SECRET":');
for (const directory of [missing, malformed]) {
	const env = { ...probeEnv, OMP_LANG: "ko", OMP_LOCALE_DIR: directory };
	const help = await command([binary, "--help"], work, env, true);
	if (!help.stdout.includes("USAGE") || !help.stdout.includes("--model") ||
		!help.stderr.includes("Could not load Korean language pack; using English.") ||
		`${help.stdout}${help.stderr}`.includes("PRIVATE_RELEASE_PACK_SECRET")) {
		throw new Error("Binary failed safe English fallback for a missing or malformed pack.");
	}
	const smoke = await command([binary, "--smoke-test"], work, env, true);
	if (!`${smoke.stdout}\n${smoke.stderr}`.includes("smoke-test: ok")) throw new Error("Fallback smoke did not complete.");
}
const tempArchive = path.join(work, manifest.archive);
await command(["/usr/bin/tar", "--format", "ustar", "-czf", tempArchive, "-C", stage, ...packageFiles], work, { ...process.env, COPYFILE_DISABLE: "1" });
const checksum = await digest(tempArchive, "sha256", "hex");
await fs.rename(tempArchive, path.join(output, manifest.archive));
await Bun.write(path.join(output, `SHA256SUMS-macos-${process.arch}`), `${checksum}  ${manifest.archive}\n`);
await Bun.write(path.join(output, `release-macos-${process.arch}.json`), `${JSON.stringify(manifest, null, 2)}\n`);
await Bun.write(path.join(output, "install.sh"), installer);
await fs.chmod(path.join(output, "install.sh"), 0o755);
console.log(`Created ${path.join(output, manifest.archive)}\nSHA256 ${checksum}`);
console.log(`Release assets: archive, SHA256SUMS-macos-${process.arch}, release-macos-${process.arch}.json, install.sh`);
