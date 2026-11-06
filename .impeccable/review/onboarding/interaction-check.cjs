const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('docs/design/liquid-glass/sources/combo-onboarding-liquid-glass.html', 'utf8');
const script = source.match(/<script>([\s\S]*?)<\/script>/)[1];
function boot(saved) {
  const document = { activeElement: null, handlers: {}, addEventListener(type, fn) { this.handlers[type] = fn; } };
  const events = {};
  const writes = [];
  const nodes = new Map();
  function node(selector) {
    if (!nodes.has(selector)) nodes.set(selector, {
      dataset: {}, attributes: {}, hidden: false, open: false, handlers: {},
      addEventListener(type, fn) { this.handlers[type] = fn; },
      setAttribute(key, value) { this.attributes[key] = value; },
      focus() { document.activeElement = this; },
      click() { this.handlers.click(); }
    });
    return nodes.get(selector);
  }
  const batteries = [node('battery-icon'), node('battery-example'), node('battery-panel')];
  const root = node('root');
  root.querySelector = node;
  root.querySelectorAll = () => batteries;
  document.getElementById = () => root;
  const window = {
    openai: { widgetState: { privateContent: saved }, setWidgetState: value => { writes.push(value); return Promise.resolve(); } },
    addEventListener: (type, fn) => { events[type] = fn; }
  };
  vm.runInNewContext(script, { document, window });
  return { root, node, batteries, writes, document, events };
}
const app = boot(null);
const trigger = app.node('[data-action="toggle-panel"]');
assert.equal(trigger.attributes['aria-expanded'], 'false');
assert.equal(app.writes.length, 0, 'Loading must not save state');
app.node('[data-action="finish"]').click();
assert.equal(app.node('[data-welcome]').hidden, true, 'Completion must be available before trying the panel');
app.node('[data-action="replay"]').click();
trigger.click();
assert.equal(trigger.attributes['aria-expanded'], 'true');
assert.equal(app.node('#og-demo-panel').inert, false);
trigger.click();
assert.equal(trigger.attributes['aria-expanded'], 'false');
assert.match(app.node('[data-instruction-title]').textContent, /已收起/);
trigger.click();
app.document.handlers.keydown({ key: 'Escape', preventDefault() {} });
assert.equal(trigger.attributes['aria-expanded'], 'false');
assert.equal(app.document.activeElement, trigger, 'Escape must restore trigger focus');
const restored = boot({ hasBattery: false, appearance: 'invalid', helpOpen: true });
assert.equal(restored.root.dataset.appearance, 'system', 'Invalid external appearance must use the default');
assert.equal(restored.batteries.every(node => node.hidden), true);
assert.equal(restored.node('[data-value]').textContent, '一个图标，查看 Wi-Fi 和声音');
restored.node('[data-help]').handlers.toggle();
assert.equal(restored.writes.length, 0, 'Restoring help state must not save it again');
restored.events['openai:set_globals']({ detail: { globals: { widgetState: { privateContent: { appearance: 'dark', reduceMotion: true, reduceTransparency: true } } } } });
assert.equal(restored.root.dataset.appearance, 'dark');
assert.equal(restored.root.dataset.reduceMotion, 'true');
assert.equal(restored.root.dataset.reduceTransparency, 'true');
assert.equal(restored.writes.length, 0, 'Restoring host state must not save it');
console.log('PASS: direct completion, replay, panel toggle, Escape/focus, no-battery copy, external-state validation and reduced-effect state.');
