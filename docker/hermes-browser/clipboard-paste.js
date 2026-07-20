import KeyTable from "../core/input/keysym.js";
import RFB from "../core/rfb.js";
import UI from "./ui.js";

let clipboardRfb;
let hostPasteTarget;
let hostPasteAttempt = 0;
let hostPasteHandledAttempt = 0;
let hostClipboardWritePending = false;
let legacyHostCopyInProgress = false;
let hostPastePrimeReleaseTimer;

const HOST_CLIPBOARD_READ_FALLBACK_DELAY_MS = 100;
const HOST_PASTE_PRIMING_TIMEOUT_MS = 1000;
const REMOTE_PASTE_SHORTCUT_DELAY_MS = 100;

function isClipboardPanelTarget(target) {
  return target instanceof Element && target.closest("#noVNC_clipboard") !== null;
}

function isPasteShortcut(event) {
  return (event.ctrlKey || event.metaKey) && !event.altKey && event.code === "KeyV";
}

function isHostPastePrimingKey(event) {
  return event.code === "MetaLeft" || event.code === "MetaRight";
}

function isRemoteClipboardShortcut(event) {
  return (
    (event.ctrlKey || event.metaKey) &&
    !event.altKey &&
    (event.code === "KeyC" || event.code === "KeyX")
  );
}

function sendClipboardText(text) {
  // noVNC 1.3 truncates the fallback clipboard payload to Latin-1.
  RFB.messages.clientCutText(UI.rfb._sock, new TextEncoder().encode(text));
}

function getHostPasteTarget() {
  if (hostPasteTarget?.isConnected) {
    return hostPasteTarget;
  }

  hostPasteTarget = document.createElement("textarea");
  hostPasteTarget.id = "noVNC_host_paste_target";
  hostPasteTarget.setAttribute("aria-hidden", "true");
  hostPasteTarget.autocomplete = "off";
  hostPasteTarget.autocapitalize = "off";
  hostPasteTarget.spellcheck = false;
  hostPasteTarget.style.position = "fixed";
  hostPasteTarget.style.left = "-1000px";
  hostPasteTarget.style.top = "0";
  hostPasteTarget.style.width = "1px";
  hostPasteTarget.style.height = "1px";
  hostPasteTarget.style.opacity = "0";

  document.body.append(hostPasteTarget);
  return hostPasteTarget;
}

function focusHostPasteTarget() {
  const hostPasteTarget = getHostPasteTarget();
  hostPasteTarget.value = "";
  hostPasteTarget.focus();
  hostPasteTarget.select();
}

function clearHostPastePrimeRelease() {
  if (hostPastePrimeReleaseTimer === undefined) {
    return;
  }

  window.clearTimeout(hostPastePrimeReleaseTimer);
  hostPastePrimeReleaseTimer = undefined;
}

function scheduleHostPastePrimeRelease() {
  clearHostPastePrimeRelease();
  hostPastePrimeReleaseTimer = window.setTimeout(() => {
    hostPastePrimeReleaseTimer = undefined;
    if (UI.rfb && document.activeElement === hostPasteTarget) {
      UI.rfb.focus();
    }
  }, HOST_PASTE_PRIMING_TIMEOUT_MS);
}

function sendRemoteControlShortcut(code) {
  const keysym = code === "KeyC" ? KeyTable.XK_c : KeyTable.XK_x;

  UI.rfb.sendKey(KeyTable.XK_Control_L, "ControlLeft", true);
  UI.rfb.sendKey(keysym, code, true);
  UI.rfb.sendKey(keysym, code, false);
  UI.rfb.sendKey(KeyTable.XK_Control_L, "ControlLeft", false);
}

function sendRemotePasteShortcut() {
  UI.rfb.sendKey(KeyTable.XK_Control_L, "ControlLeft", true);
  UI.rfb.sendKey(KeyTable.XK_v, "KeyV", true);
  UI.rfb.sendKey(KeyTable.XK_v, "KeyV", false);
  UI.rfb.sendKey(KeyTable.XK_Control_L, "ControlLeft", false);
  UI.rfb.focus();
}

function getTypeableKeysym(character) {
  if (character === "\n" || character === "\r") {
    return KeyTable.XK_Return;
  }

  if (character === "\t") {
    return KeyTable.XK_Tab;
  }

  const codePoint = character.codePointAt(0);
  if (codePoint >= 0x20 && codePoint <= 0x7e) {
    return codePoint;
  }

  return null;
}

function getTypeableKeysyms(text) {
  return Array.from(text.replace(/\r\n/g, "\n").replace(/\r/g, "\n"), getTypeableKeysym);
}

function typeTextToRemote(text) {
  const keysyms = getTypeableKeysyms(text);
  if (keysyms.some((keysym) => keysym === null)) {
    return false;
  }

  for (const keysym of keysyms) {
    UI.rfb.sendKey(keysym, "", true);
    UI.rfb.sendKey(keysym, "", false);
  }

  UI.rfb.focus();
  return true;
}

function scheduleRemotePasteShortcut() {
  window.setTimeout(sendRemotePasteShortcut, REMOTE_PASTE_SHORTCUT_DELAY_MS);
}

function pasteTextToRemote(text) {
  if (typeTextToRemote(text)) {
    return;
  }

  sendClipboardText(text);
  scheduleRemotePasteShortcut();
}

function scheduleHostClipboardReadFallback(pasteAttempt) {
  if (!navigator.clipboard?.readText) {
    return;
  }

  navigator.clipboard
    .readText()
    .then((text) => {
      window.setTimeout(() => {
        if (hostPasteHandledAttempt >= pasteAttempt || typeof text !== "string") {
          return;
        }

        hostPasteHandledAttempt = pasteAttempt;
        pasteTextToRemote(text);
      }, HOST_CLIPBOARD_READ_FALLBACK_DELAY_MS);
    })
    .catch(() => {});
}

function decodeVncClipboardText(text) {
  if (Array.from(text).some((character) => character.charCodeAt(0) > 0xff)) {
    return text;
  }

  try {
    const bytes = Uint8Array.from(text, (character) => character.charCodeAt(0));
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return text;
  }
}

function copyTextWithDocument(text) {
  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  legacyHostCopyInProgress = true;

  try {
    document.body.append(textarea);
    textarea.select();
    document.execCommand("copy");
  } finally {
    textarea.remove();
    legacyHostCopyInProgress = false;
    UI.rfb.focus();
  }
}

function writeHostClipboard(text) {
  if (navigator.clipboard?.writeText) {
    navigator.clipboard.writeText(text).catch(() => copyTextWithDocument(text));
    return;
  }

  copyTextWithDocument(text);
}

function receiveRemoteClipboard(event) {
  const rawText = event.detail?.text;
  if (typeof rawText !== "string") {
    return;
  }

  const text = decodeVncClipboardText(rawText);
  document.querySelector("#noVNC_clipboard_text").value = text;
  if (!hostClipboardWritePending) {
    return;
  }

  hostClipboardWritePending = false;
  writeHostClipboard(text);
}

function ensureClipboardReceiver() {
  if (clipboardRfb === UI.rfb) {
    return;
  }

  clipboardRfb?.removeEventListener("clipboard", receiveRemoteClipboard);
  clipboardRfb = UI.rfb;
  clipboardRfb.addEventListener("clipboard", receiveRemoteClipboard);
}

function beginRemoteClipboardTransfer(code) {
  ensureClipboardReceiver();
  clearHostPastePrimeRelease();
  hostClipboardWritePending = true;
  sendRemoteControlShortcut(code);
  UI.rfb.focus();
}

function handleRemoteClipboardCommand(event, code) {
  if (!UI.rfb || legacyHostCopyInProgress || isClipboardPanelTarget(event.target)) {
    return;
  }

  event.preventDefault();
  event.stopImmediatePropagation();
  beginRemoteClipboardTransfer(code);
}

document.addEventListener(
  "keydown",
  (event) => {
    if (!UI.rfb || isClipboardPanelTarget(event.target)) {
      return;
    }

    if (isHostPastePrimingKey(event)) {
      event.stopImmediatePropagation();
      focusHostPasteTarget();
      scheduleHostPastePrimeRelease();
      return;
    }

    if (isRemoteClipboardShortcut(event)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      beginRemoteClipboardTransfer(event.code);
      return;
    }

    if (!isPasteShortcut(event)) {
      return;
    }

    event.stopImmediatePropagation();
    clearHostPastePrimeRelease();
    hostPasteAttempt += 1;
    focusHostPasteTarget();
    scheduleHostClipboardReadFallback(hostPasteAttempt);
  },
  true
);

document.addEventListener("copy", (event) => handleRemoteClipboardCommand(event, "KeyC"), true);

document.addEventListener("cut", (event) => handleRemoteClipboardCommand(event, "KeyX"), true);

document.addEventListener(
  "paste",
  (event) => {
    if (!UI.rfb || isClipboardPanelTarget(event.target)) {
      return;
    }

    const text = event.clipboardData?.getData("text/plain");
    if (typeof text !== "string") {
      UI.rfb.focus();
      return;
    }

    event.preventDefault();
    clearHostPastePrimeRelease();
    hostPasteHandledAttempt = hostPasteAttempt;
    pasteTextToRemote(text);
  },
  true
);
