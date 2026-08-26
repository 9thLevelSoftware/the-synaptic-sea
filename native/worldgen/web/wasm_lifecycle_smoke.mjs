import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const root = process.argv[2] ?? path.resolve('addons/derelict/bin/web');
const corpusPath = process.argv[3] ?? path.resolve('native/worldgen/tests/adapter_parity/corpus.json');
const require = createRequire(import.meta.url);
const binding = require(path.resolve(root, 'derelict_wasm.js'));
const wasm = fs.readFileSync(path.resolve(root, 'derelict_wasm_bg.wasm'));
if (typeof binding.initSync === 'function') binding.initSync({ module: wasm });
const parse = (raw) => JSON.parse(raw);
const cap = parse(binding.capabilities());
const manifest = parse(binding.generator_manifest());
const vectors = JSON.parse(fs.readFileSync(corpusPath, 'utf8'));
const expectedDomains = ['world', 'site', 'gameplay', 'presentation'];
const expectedAdapterSchemas = {
  lifecycle_result: 'procgen-lifecycle-result-2',
  capabilities: 'procgen-capabilities-1',
  generator_manifest: 'procgen-generator-manifest-1',
};
const expectedExportSchemas = {
  procgen_request: 'procgen-request-1',
  procgen_bundle: 'procgen-bundle-2',
  world_ir: 'world-ir-2',
  site_ir: 'site-ir-1',
  gameplay_ir: 'gameplay-ir-1',
  presentation_ir: 'presentation-ir-1',
  generation_trace: 'generation-trace-1',
  adaptive_proposal: 'adaptive-proposal-1',
};
const canonical = (value) => {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
};
const equal = (left, right) => JSON.stringify(canonical(left)) === JSON.stringify(canonical(right));
if (cap.schema_version !== 'procgen-capabilities-1' || cap.adapter_kind !== 'web'
    || cap.target !== 'wasm32-unknown-unknown' || cap.supports_sync !== true
    || cap.supports_async !== true || cap.supports_cancel !== true
    || cap.worker_mode !== 'cooperative' || cap.worker_count !== 0
    || cap.queue_capacity !== 8 || cap.retained_results !== 16
    || cap.max_request_bytes !== 65536 || cap.max_entities !== 4096
    || cap.max_trace_entries !== 4096 || cap.max_events !== 32
    || cap.deadline_ms !== 2000 || !equal(cap.supported_domains, expectedDomains)
    || !equal(cap.schemas, expectedAdapterSchemas)) throw new Error('capabilities contract mismatch');
if (manifest.schema_version !== 'procgen-generator-manifest-1'
    || !/^[0-9a-f]{40}$/.test(manifest.rust_source_commit)
    || manifest.generator_version !== 3
    || manifest.content_manifest_hash !== vectors[0].request.content_manifest_hash
    || !equal(manifest.export_schemas, expectedExportSchemas)
    || !equal(manifest.adapter_schemas, expectedAdapterSchemas)
    || manifest.target !== 'wasm32-unknown-unknown'
    || typeof manifest.dirty_development !== 'boolean') throw new Error('manifest contract mismatch');
for (const vector of vectors) {
  if (!Number.isSafeInteger(vector.request.world_seed)
      || !Number.isSafeInteger(vector.request.presentation.seed)) {
    throw new Error(`${vector.name} contains a non-portable JSON integer`);
  }
}
const ids = [];
for (const vector of vectors.slice(0, 8)) {
  const accepted = parse(binding.generate_bundle_async(JSON.stringify(vector.request)));
  if (!equal(accepted.events, ['admitted', 'queued'])) throw new Error(`${vector.name} admission events mismatch`);
  ids.push(BigInt(accepted.request_id));
}
if (ids.join(',') !== '1,2,3,4,5,6,7,8') throw new Error(`queue ids mismatch: ${ids}`);
const overload = parse(binding.generate_bundle_async(JSON.stringify(vectors[0].request)));
if (overload.request_id !== null || overload.failure?.code !== 'overload'
    || !equal(overload.events, ['rejected', 'overloaded'])) throw new Error('overload contract mismatch');
const recovered = parse(binding.poll(ids[0]));
if (recovered.bundle?.semantic_hash !== vectors[0].expected_semantic_hash) {
  throw new Error(`queue recovery mismatch: actual=${recovered.bundle?.semantic_hash ?? 'none'} expected=${vectors[0].expected_semantic_hash}`);
}
const cancelled = parse(binding.generate_bundle_async(JSON.stringify(vectors[0].request)));
const cancelId = BigInt(cancelled.request_id);
if (cancelId !== 9n) throw new Error(`recovery id mismatch: ${cancelId}`);
if (parse(binding.cancel(cancelId)).failure?.code !== 'cancellation') throw new Error('cancel contract mismatch');
if (parse(binding.cancel(cancelId)).failure?.code !== 'cancellation') throw new Error('cancel idempotence mismatch');
if (parse(binding.poll(cancelId)).failure?.code !== 'cancellation') throw new Error('cancel poll mismatch');
if (parse(binding.poll(cancelId)).failure?.code !== 'result_consumed') throw new Error('cancel consumption mismatch');
for (let index = 1; index < ids.length; index += 1) {
  const terminal = parse(binding.poll(ids[index]));
  if (terminal.bundle?.semantic_hash !== vectors[index].expected_semantic_hash) {
    throw new Error(`${vectors[index].name} queued hash mismatch`);
  }
}
for (const vector of vectors) {
  const raw = JSON.stringify(vector.request);
  const sync = parse(binding.generate_bundle(raw));
  if (sync.bundle?.semantic_hash !== vector.expected_semantic_hash) throw new Error(`${vector.name} sync hash mismatch`);
  const accepted = parse(binding.generate_bundle_async(raw));
  const id = BigInt(accepted.request_id);
  const terminal = parse(binding.poll(id));
  if (terminal.bundle?.semantic_hash !== vector.expected_semantic_hash) throw new Error(`${vector.name} async hash mismatch`);
  const consumed = parse(binding.poll(id));
  if (consumed.failure?.code !== 'result_consumed') throw new Error(`${vector.name} consumed contract mismatch`);
}
console.log('WASM_LIFECYCLE_SMOKE: PASS');
