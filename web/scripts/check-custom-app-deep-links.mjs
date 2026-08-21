import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const webDirectory = path.resolve(scriptDirectory, "..");

async function readSource(relativePath) {
  return readFile(path.resolve(webDirectory, relativePath), "utf8");
}

function requireText(source, text, message, failures) {
  if (!source.includes(text)) failures.push(message);
}

async function main() {
  const frame = await readSource("src/shell/CustomAppFrame.tsx");
  const mailbox = await readSource("src/shell/customAppDeepLinks.ts");
  const failures = [];
  const loadStart = frame.indexOf("const onLoad = useCallback");
  const loadEnd = frame.indexOf("useEffect(() => {", loadStart);
  const loadLifecycle = frame.slice(loadStart, loadEnd);

  requireText(
    mailbox,
    "message.action === 'deepLink' && isRecord(message.data)",
    "early delivery does not validate deep-link messages",
    failures,
  );
  requireText(
    frame,
    "deepLinkReadyRef.current && isCustomAppDeepLinkMessage(message)",
    "ready custom apps do not receive deep links before SDK readiness",
    failures,
  );
  requireText(
    frame,
    "outboxRef.current = deliverReadyDeepLinks",
    "queued deep links are not released by the early readiness handshake",
    failures,
  );
  requireText(
    frame,
    "msg.type === 'sdphoneDeepLinkReady'",
    "custom app frames do not consume the early readiness handshake",
    failures,
  );
  requireText(
    frame,
    "Reflect.get(win, 'sdPhoneDeepLinkReady') === true",
    "iframe load does not recover a readiness message sent before the host subscribed",
    failures,
  );

  if (loadLifecycle.includes("outboxRef.current = []")) {
    failures.push("iframe load still destroys messages queued during cold launch");
  }

  if (failures.length > 0) {
    process.stderr.write(`${failures.join("\n")}\n`);
    process.exitCode = 1;
    return;
  }

  process.stdout.write("Validated custom-app cold deep-link delivery.\n");
}

await main();
