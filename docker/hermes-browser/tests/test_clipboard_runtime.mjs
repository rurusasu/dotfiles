import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../clipboard-paste.js", import.meta.url), "utf8").replace(
  /^import .*;\n/gm,
  ""
);

// Exercise the shipped event handlers. Only DOM, clipboard and RFB boundaries
// are replaced; execCommand dispatches copy synchronously like the browser.
function viewer({ clipboard, copyThrows = false } = {}) {
  const handlers = new Map();
  const children = [];
  const keys = [];
  const writes = [];
  const cutTexts = [];
  const timers = [];
  const panel = { value: "" };
  let focusCount = 0;
  let copyEvent;
  class Element {
    style = {};
    value = "";
    isConnected = false;
    closest() {
      return null;
    }
    setAttribute() {}
    focus() {
      document.activeElement = this;
    }
    select() {
      this.focus();
    }
    remove() {
      this.isConnected = false;
      children.splice(children.indexOf(this), 1);
    }
  }
  function dispatch(type, fields = {}) {
    const event = {
      target: document.activeElement,
      prevented: false,
      preventDefault() {
        this.prevented = true;
      },
      stopImmediatePropagation() {},
      ...fields,
    };
    handlers.get(type)?.(event);
    return event;
  }
  const document = {
    activeElement: null,
    addEventListener(type, handler) {
      handlers.set(type, handler);
    },
    createElement() {
      return new Element();
    },
    querySelector() {
      return panel;
    },
    body: {
      append(element) {
        children.push(element);
        element.isConnected = true;
      },
    },
    execCommand(command) {
      assert.equal(command, "copy");
      copyEvent = dispatch("copy");
      if (copyThrows) {
        throw new Error("document copy failed");
      }
      if (!copyEvent.prevented) {
        writes.push(document.activeElement.value);
      }
      return !copyEvent.prevented;
    },
  };
  const rfb = {
    _sock: {},
    sendKey(...args) {
      keys.push(args);
    },
    focus() {
      focusCount += 1;
      document.activeElement = null;
    },
    addEventListener(type, handler) {
      handlers.set(`rfb:${type}`, handler);
    },
  };
  const keyTable = {
    XK_Control_L: 0xffe3,
    XK_c: 0x63,
    XK_x: 0x78,
    XK_v: 0x76,
    XK_Return: 0xff0d,
    XK_Tab: 0xff09,
  };
  vm.runInNewContext(source, {
    document,
    navigator: { clipboard },
    window: {
      setTimeout(callback) {
        timers.push(callback);
        return timers.length;
      },
      clearTimeout() {},
    },
    Element,
    TextEncoder,
    TextDecoder,
    UI: { rfb },
    KeyTable: keyTable,
    RFB: {
      messages: {
        clientCutText(socket, bytes) {
          assert.equal(socket, rfb._sock);
          cutTexts.push(Array.from(bytes));
        },
      },
    },
  });
  return {
    dispatch,
    children,
    keys,
    writes,
    cutTexts,
    panel,
    timers,
    get copyEvent() {
      return copyEvent;
    },
    get focusCount() {
      return focusCount;
    },
    copy(text) {
      dispatch("keydown", { ctrlKey: true, code: "KeyC" });
      dispatch("rfb:clipboard", { detail: { text } });
    },
  };
}

const copyKeys = [
  [0xffe3, "ControlLeft", true],
  [0x63, "KeyC", true],
  [0x63, "KeyC", false],
  [0xffe3, "ControlLeft", false],
];

test("missing Clipboard API copies remote text without reentering remote copy", () => {
  const page = viewer();
  page.copy("remote 日本語");
  assert.deepEqual(page.writes, ["remote 日本語"]);
  assert.equal(page.copyEvent.prevented, false);
  assert.deepEqual(page.keys, copyKeys);
  assert.equal(page.children.length, 0);
  assert.equal(page.focusCount, 2);
  page.dispatch("rfb:clipboard", { detail: { text: "unsolicited" } });
  assert.deepEqual(page.writes, ["remote 日本語"]);
  assert.equal(page.panel.value, "unsolicited");
  page.dispatch("copy");
  assert.deepEqual(page.keys, [...copyKeys, ...copyKeys]);
});

test("denied Clipboard API falls back once and leaves later copy commands enabled", async () => {
  const attempts = [];
  const page = viewer({
    clipboard: {
      writeText(text) {
        attempts.push(text);
        return Promise.reject(new DOMException("Denied", "NotAllowedError"));
      },
    },
  });
  page.copy("permission denied");
  await Promise.resolve();
  assert.deepEqual(attempts, ["permission denied"]);
  assert.deepEqual(page.writes, ["permission denied"]);
  assert.deepEqual(page.keys, copyKeys);
  page.dispatch("cut");
  assert.deepEqual(page.keys.slice(4), [
    [0xffe3, "ControlLeft", true],
    [0x78, "KeyX", true],
    [0x78, "KeyX", false],
    [0xffe3, "ControlLeft", false],
  ]);
});

test("successful Clipboard API does not invoke document copy", async () => {
  const writes = [];
  const page = viewer({ clipboard: { writeText: async (text) => writes.push(text) } });
  page.copy("API copy");
  await Promise.resolve();
  assert.deepEqual(writes, ["API copy"]);
  assert.deepEqual(page.writes, []);
  assert.equal(page.copyEvent, undefined);
});

test("throwing document copy releases its reentrancy guard and removes textarea", () => {
  const page = viewer({ copyThrows: true });
  assert.throws(() => page.copy("failed"), /document copy failed/);
  assert.equal(page.children.length, 0);
  assert.equal(page.focusCount, 2);
  page.dispatch("copy");
  assert.deepEqual(page.keys, [...copyKeys, ...copyKeys]);
});

test("host paste event types ASCII once even when Clipboard API read resolves", async () => {
  const page = viewer({ clipboard: { readText: async () => "duplicate" } });
  page.dispatch("keydown", { metaKey: true, code: "KeyV" });
  const event = page.dispatch("paste", { clipboardData: { getData: () => "A\r\nB" } });
  await Promise.resolve();
  page.timers.forEach((callback) => callback());
  assert.equal(event.prevented, true);
  assert.deepEqual(page.keys, [
    [0x41, "", true],
    [0x41, "", false],
    [0xff0d, "", true],
    [0xff0d, "", false],
    [0x42, "", true],
    [0x42, "", false],
  ]);
  assert.deepEqual(page.cutTexts, []);
});

test("host Unicode paste sends UTF-8 clipboard before remote Ctrl+V", () => {
  const page = viewer();
  page.dispatch("paste", { clipboardData: { getData: () => "日本語" } });
  assert.deepEqual(page.cutTexts, [[230, 151, 165, 230, 156, 172, 232, 170, 158]]);
  assert.deepEqual(page.keys, []);
  page.timers.forEach((callback) => callback());
  assert.deepEqual(page.keys, [
    [0xffe3, "ControlLeft", true],
    [0x76, "KeyV", true],
    [0x76, "KeyV", false],
    [0xffe3, "ControlLeft", false],
  ]);
});
