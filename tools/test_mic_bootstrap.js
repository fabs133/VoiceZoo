// Checks the microphone permission state machine that lives as embedded JS in
// platform/web_audio_recorder.gd.
//
//   node tools/test_mic_bootstrap.js
//
// NOT wired into run_checks.ps1 on purpose: that script needs only Godot, and
// this needs Node. Run it by hand after touching _JS_BOOTSTRAP.
//
// It exists because the GDScript suite cannot reach this code at all - there is
// no browser in a headless test run - and this is exactly where the bug that
// broke recording on every device lived: permission was tied to AudioContext
// creation, so a context failure reported itself to the guest as "no
// microphone", and the request was fired outside a user gesture, where iOS
// Safari will not open a prompt.

const fs = require('fs');
const path = require('path');

const RECORDER = path.join(__dirname, '..', 'platform', 'web_audio_recorder.gd');
const src = fs.readFileSync(RECORDER, 'utf8');
const match = src.match(/const _JS_BOOTSTRAP := """([\s\S]*?)"""/);
if (!match) {
  console.error(`FAIL  could not find _JS_BOOTSTRAP in ${RECORDER}`);
  process.exit(1);
}
const BOOTSTRAP = match[1];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}  (got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)})`);
}

// contextBroken makes the AudioContext constructor throw, to prove permission
// no longer depends on one. gum decides how getUserMedia resolves.
function boot({ contextBroken = false, gum = 'grant', noMediaDevices = false } = {}) {
  const listeners = {};
  let gumCalls = 0;

  global.window = {
    addEventListener: (type, fn) => { (listeners[type] = listeners[type] || []).push(fn); },
    AudioContext: contextBroken
      ? function () { throw new Error('AudioContext blocked'); }
      : function () { this.state = 'running'; this.sampleRate = 48000; this.resume = () => {}; },
  };

  // Node 22 ships a real `navigator` global defined as an accessor, so a plain
  // assignment is silently dropped. Redefine the property instead.
  const fakeNavigator = noMediaDevices ? {} : {
    mediaDevices: {
      getUserMedia: () => {
        gumCalls++;
        if (gum === 'grant') return Promise.resolve({ getTracks: () => [] });
        const err = new Error(gum === 'deny' ? 'denied by user' : 'no device');
        err.name = gum === 'deny' ? 'NotAllowedError' : 'NotFoundError';
        return Promise.reject(err);
      },
    },
  };
  Object.defineProperty(global, 'navigator', {
    value: fakeNavigator, configurable: true, writable: true, enumerable: true,
  });

  (0, eval)(BOOTSTRAP);
  return {
    mic: global.window.__vz_mic,
    tap: () => (listeners['touchend'] || []).forEach((fn) => fn()),
    gumCalls: () => gumCalls,
  };
}

const flush = () => new Promise((r) => setImmediate(r));

(async () => {
  // 1. Arming must not prompt, and must report PENDING rather than UNKNOWN.
  //    Reporting UNKNOWN is what used to fall through to "Kein Mikrofon
  //    verfuegbar" without the waiting state ever appearing.
  let h = boot();
  h.mic.arm();
  check('arm() does not call getUserMedia', h.gumCalls(), 0);
  check('arm() reports PENDING', h.mic.permission, 1);
  check('arm() raises the flag', h.mic.wantPermission, true);

  // 2. A real gesture is what actually prompts.
  h.tap();
  check('a tap calls getUserMedia once', h.gumCalls(), 1);
  check('the flag is cleared once requested', h.mic.wantPermission, false);
  await flush();
  check('granted -> GRANTED', h.mic.permission, 2);
  h.tap();
  check('no second prompt after grant', h.gumCalls(), 1);

  // 3. The decoupling: a dead AudioContext must not read as "no microphone".
  h = boot({ contextBroken: true });
  h.mic.arm();
  h.tap();
  await flush();
  check('broken AudioContext still grants', h.mic.permission, 2);
  check('and is not reported as UNSUPPORTED', h.mic.permission === 4, false);

  // 4. Refusal stays distinguishable from a missing device: only the first is
  //    something the guest can go and undo.
  h = boot({ gum: 'deny' });
  h.mic.arm(); h.tap(); await flush();
  check('refusal -> DENIED', h.mic.permission, 3);

  h = boot({ gum: 'notfound' });
  h.mic.arm(); h.tap(); await flush();
  check('missing device -> UNSUPPORTED', h.mic.permission, 4);

  // 5. No getUserMedia at all, e.g. an insecure origin.
  h = boot({ noMediaDevices: true });
  h.mic.arm(); h.tap();
  check('no getUserMedia -> UNSUPPORTED', h.mic.permission, 4);
  check('and says why', /HTTPS/.test(h.mic.error), true);

  // 6. release() must clear the arming flags, or a stale flag would fire a
  //    prompt on some later unrelated tap.
  h = boot();
  h.mic.arm(); h.tap(); await flush();
  h.mic.release();
  check('release resets permission', h.mic.permission, 0);
  check('release clears wantPermission', h.mic.wantPermission, false);
  check('release clears requesting', h.mic.requesting, false);
  h.tap();
  check('a tap after release does not prompt', h.gumCalls(), 1);

  // 7. Idempotence is what makes _ensure_bridge() safe to retry on every call.
  h = boot();
  h.mic.arm(); h.tap(); await flush();
  (0, eval)(BOOTSTRAP);
  check('re-eval keeps the granted state', global.window.__vz_mic.permission, 2);
  check('re-eval keeps the same object', global.window.__vz_mic === h.mic, true);

  console.log(failures === 0 ? '\nALL JS LOGIC CHECKS PASSED' : `\n${failures} JS LOGIC CHECK(S) FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})();
