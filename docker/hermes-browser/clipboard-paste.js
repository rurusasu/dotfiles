import KeyTable from "../core/input/keysym.js";
import RFB from "../core/rfb.js";
import UI from "./ui.js";

let clipboardRfb;
let hostClipboardWritePending = false;
let legacyHostCopyInProgress = false;

function isClipboardPanelTarget(target) {
  return target instanceof Element && target.closest("#noVNC_clipboard") !== null;
}

function isPasteShortcut(event) {
  return (event.ctrlKey || event.metaKey) && !event.altKey && event.code === "KeyV";
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

function sendRemoteControlShortcut(code) {
  const keysym = code === "KeyC" ? KeyTable.XK_c : KeyTable.XK_x;

  UI.rfb.sendKey(KeyTable.XK_Control_L, "ControlLeft", true);
  UI.rfb.sendKey(keysym, code, true);
  UI.rfb.sendKey(keysym, code, false);
  UI.rfb.sendKey(KeyTable.XK_Control_L, "ControlLeft", false);
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
    UI.rfb.blur();
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
    sendClipboardText(text);
    UI.rfb.sendKey(KeyTable.XK_Control_L, "ControlLeft", true);
    UI.rfb.sendKey(KeyTable.XK_v, "KeyV", true);
    UI.rfb.sendKey(KeyTable.XK_v, "KeyV", false);
    UI.rfb.sendKey(KeyTable.XK_Control_L, "ControlLeft", false);
    UI.rfb.focus();
  },
  true
);
