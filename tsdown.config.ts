import { defineConfig } from 'tsdown';
import { compile } from 'svelte/compiler';
import { gzipSync } from 'node:zlib'
const sveltePlugin = () => ({
  name: 'svelte',
  transform: {
    filter: { id: /\.svelte$/ },
    handler(code: string, id: string) {
      const compiled = compile(code, {
        filename: id,
        generate: 'client',
        css: 'injected',
      });

      return {
        code: compiled.js.code,
        map: compiled.js.map,
      };
    },
  },
});

function obfuscateScript(script: string, kind: "sh" | "py"): string {
  const key1 = (Math.random() * 256) & 0xff, key2 = (Math.random() * 256) & 0xff;
  const decryptPython = (x: string, f: string) => `import sys,zlib,base64;i=${x};i=bytes([x ^ ${key1} for x in i]);i=zlib.decompress(i);i=bytes([x ^ ${key2} for x in i]);${f}(str(i))`;
  const bytes = [...gzipSync(new Uint8Array([...new TextEncoder().encode(script)].map(b => b ^ key2)))].map(a => a ^ key1);
  switch (kind) {
    case "sh":
      return `eval "$(echo ${btoa(String.fromCharCode(...bytes))} | base64 -d | python3 -c '${decryptPython('sys.stdin.read()', 'print')}')"`;
    case "py":
      return decryptPython(`bytes(${JSON.stringify(bytes)})`, "exec");
  }
}

const obfuscateScriptPlugin = (kind: "sh" | "py") => ({
  name: 'obfuscate-script',
  transform: {
    filter: {id: new RegExp(`\.${kind}$`)},
    handler(code: string, id: string) {
      const s = obfuscateScript(code,kind);
      return {code: `export const script = ${JSON.stringify(s)}`}
    }
  }
});

export default defineConfig({
  platform: 'browser',
  entry: 'src/bootstrap/index.ts',
  dts: false,
  exports: true,
  minify: true,
  plugins: [sveltePlugin(),obfuscateScriptPlugin("sh"),obfuscateScriptPlugin("py")],
  loader: {
    '.svg': 'text',
    '.webp': 'dataurl',
  },
});
