import KeyTable from "../core/input/keysym.js";
import RFB from "../core/rfb.js";
import UI from "./ui.js";

function isClipboardPanelTarget(target) {
  return target instanceof Element && target.closest("#noVNC_clipboard") !== null;
}

function isPasteShortcut(event) {
  return (event.ctrlKey || event.metaKey) && !event.altKey && event.code === "KeyV";
}

function sendClipboardText(text) {
  // noVNC 1.3 truncates the fallback clipboard payload to Latin-1.
  RFB.messages.clientCutText(UI.rfb._sock, new TextEncoder().encode(text));
}

document.addEventListener(
  "keydown",
  (event) => {
    if (!UI.rfb || isClipboardPanelTarget(event.target) || !isPasteShortcut(event)) {
      return;
    }

    event.stopImmediatePropagation();
    UI.rfb.blur();
  },
  true
);

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
