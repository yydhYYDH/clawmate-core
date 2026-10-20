const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const toolsRoot = process.env.STARTER_DEVECO || '/Applications/DevEco-Studio.app/Contents';
const ts = require(path.join(toolsRoot, 'tools/hvigor/hvigor/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');

function loader(mocks = {}) {
  const cache = new Map();
  function load(name, parent = root) {
    if (Object.hasOwn(mocks, name)) return mocks[name];
    if (name.startsWith('@')) throw new Error('Test must explicitly mock SDK module: ' + name);
    const filename = path.resolve(parent, name) + '.ets';
    const relative = path.relative(root, filename).replace(/\.ets$/, '');
    if (Object.hasOwn(mocks, relative)) return mocks[relative];
    if (cache.has(filename)) return cache.get(filename).exports;
    const module = { exports: {} };
    cache.set(filename, module);
    const source = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
    }).outputText;
    vm.runInThisContext('(function(require,module,exports){' + source + '\n})', { filename })(
      dependency => load(dependency, path.dirname(filename)), module, module.exports);
    return module.exports;
  }
  return name => load('./' + name);
}
module.exports = { loader };
