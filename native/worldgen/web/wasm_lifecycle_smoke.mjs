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
  lifecycle_result: 'procgen-lifecycle-result-4',
  capabilities: 'procgen-capabilities-3',
  generator_manifest: 'procgen-generator-manifest-3',
};
const expectedExportSchemas = {
  procgen_request: 'procgen-request-2',
  procgen_bundle: 'procgen-bundle-4',
  world_ir: 'world-ir-2',
  site_ir: 'site-ir-2',
  gameplay_ir: 'gameplay-ir-2',
  presentation_ir: 'presentation-ir-2',
  generation_trace: 'generation-trace-3',
  adaptive_proposal: 'adaptive-proposal-1',
};
const expectedChannels = [
  'world.archetype', 'world.biome', 'world.hazard', 'world.resource', 'world.landmark',
  'world.route_cost', 'site.structural', 'site.mission_template', 'site.gate_order',
  'site.functional_props', 'site.spatial_annotations', 'meta', 'hull', 'template',
  'topology', 'residual_fill', 'door', 'furnish', 'story', 'intact', 'breach', 'scorch',
  'seal', 'bodies', 'fracture', 'debris', 'loot', 'gameplay.creature_blueprint',
  'gameplay.creature_ability', 'gameplay.creature_material', 'gameplay.encounter_candidate',
  'gameplay.encounter_faction', 'gameplay.encounter_reward', 'gameplay.encounter_selection',
  'gameplay.item_family', 'gameplay.item_affix', 'presentation.asset_assembly',
];
const canonical = (value) => {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
};
const equal = (left, right) => JSON.stringify(canonical(left)) === JSON.stringify(canonical(right));
const parseLifecycle = (raw, name) => {
  const result = parse(raw);
  const statuses = ['accepted', 'queued', 'running', 'cancel_requested', 'completed', 'failed'];
  const events = ['rejected', 'admitted', 'queued', 'started', 'cancel_requested', 'cancelled',
    'timed_out', 'completed', 'failed', 'overloaded', 'result_consumed', 'result_expired', 'shutdown'];
  if (result?.schema_version !== 'procgen-lifecycle-result-4'
      || !statuses.includes(result.status) || !Array.isArray(result.events)
      || result.events.length < 1 || result.events.length > 32
      || result.events.some((event) => !events.includes(event))) {
    throw new Error(`${name} lifecycle schema contract mismatch`);
  }
  return result;
};
const boundedArray = (value, max, label) => {
  if (!Array.isArray(value) || value.length > max) throw new Error(`${label} bounds mismatch`);
};
const assertBundleContract = (bundle, name) => {
  if (bundle?.schema_version !== 'procgen-bundle-4'
      || bundle.world_ir?.schema_version !== 'world-ir-2'
      || bundle.site_ir?.schema_version !== 'site-ir-2'
      || bundle.gameplay_ir?.schema_version !== 'gameplay-ir-2'
      || bundle.presentation_ir?.schema_version !== 'presentation-ir-2'
      || bundle.trace?.schema_version !== 'generation-trace-3'
      || !equal(bundle.version?.export_schemas, expectedExportSchemas)) {
    throw new Error(`${name} bundle schema contract mismatch`);
  }
  const request = bundle.request;
  if (request?.schema_version !== 'procgen-request-2'
      || request.generator_version !== 3 || !Array.isArray(request.requested_domains)
      || request.requested_domains.length < 1 || request.requested_domains.length > 4
      || request.player_model?.schema_version !== 'player-model-2') {
    throw new Error(`${name} request/player model contract mismatch`);
  }
  boundedArray(request.player_model.signals, 4, `${name} player signals`);
  const signalKinds = ['combat_mastery', 'damage_pressure', 'resource_pressure', 'objective_pace'];
  request.player_model.signals.forEach((signal, index) => {
    if (!signalKinds.includes(signal.kind) || !Number.isSafeInteger(signal.value_bp)
        || signal.value_bp > 10000 || (index > 0 && signalKinds.indexOf(signal.kind) <= signalKinds.indexOf(request.player_model.signals[index - 1].kind))) {
      throw new Error(`${name} typed player signal contract mismatch`);
    }
  });
  const gameplay = bundle.gameplay_ir;
  boundedArray(gameplay.creature_blueprints, 64, `${name} creature blueprints`);
  boundedArray(gameplay.items, 64, `${name} items`);
  boundedArray(gameplay.drops, 4096, `${name} drops`);
  boundedArray(gameplay.decisions, 4096, `${name} gameplay decisions`);
  if (gameplay.encounter?.schema_version !== 'encounter-output-2'
      || !Array.isArray(gameplay.encounter.spawns) || gameplay.encounter.spawns.length > 4096
      || gameplay.encounter.total_threat > 100000 || gameplay.encounter.total_performance > 100000
      || gameplay.encounter.total_reward_value > 1000000
      || !equal(gameplay.encounter.trace.channel_ids, ['gameplay.encounter_candidate', 'gameplay.encounter_faction', 'gameplay.encounter_reward'])
      || !Array.isArray(gameplay.encounter.trace.player_values_bp)
      || gameplay.encounter.trace.player_values_bp.length !== 4) {
    throw new Error(`${name} encounter contract mismatch`);
  }
  gameplay.items.forEach((item) => {
    if (typeof item.id !== 'string' || typeof item.family_id !== 'string' || typeof item.rarity_id !== 'string'
        || !Array.isArray(item.affixes) || item.affixes.length > 3 || item.economy_value > 100000) {
      throw new Error(`${name} item contract mismatch`);
    }
  });
  gameplay.creature_blueprints.forEach((creature) => {
    if (typeof creature.id !== 'string' || typeof creature.body_plan_id !== 'string'
        || typeof creature.ability_id !== 'string' || creature.threat_cost > 65535
        || creature.performance_cost > 65535 || creature.instance_cap > 65535) {
      throw new Error(`${name} creature contract mismatch`);
    }
  });
  const presentation = bundle.presentation_ir;
  boundedArray(presentation.instructions, 128, `${name} presentation instructions`);
  boundedArray(presentation.decisions, 128, `${name} presentation decisions`);
  boundedArray(presentation.repairs, 1, `${name} presentation repairs`);
  presentation.instructions.forEach((instruction) => {
    if (typeof instruction.subject_id !== 'string' || instruction.asset_ids?.length !== 1
        || instruction.adapter_binding_ids?.length !== 1) throw new Error(`${name} presentation binding mismatch`);
  });
  if (!equal(bundle.trace.rng_channels, expectedChannels)) throw new Error(`${name} generation trace channels mismatch`);
  boundedArray(bundle.trace.candidate_decisions, 4096, `${name} trace candidates`);
  boundedArray(bundle.trace.failed_constraints, 4096, `${name} trace failures`);
  boundedArray(bundle.trace.repairs, 4096, `${name} trace repairs`);
  boundedArray(bundle.trace.retries, 4096, `${name} trace retries`);
  const site = bundle.site_ir;
  if (!Object.hasOwn(site, 'mission_graph') || !Object.hasOwn(site, 'navigation')
      || !Object.hasOwn(site, 'functional_props') || !Object.hasOwn(site, 'spatial_annotations')) {
    throw new Error(`${name} SiteIR v2 overlay missing`);
  }
};
if (cap.schema_version !== 'procgen-capabilities-3' || cap.adapter_kind !== 'web'
    || cap.target !== 'wasm32-unknown-unknown' || cap.supports_sync !== true
    || cap.supports_async !== true || cap.supports_cancel !== true
    || cap.worker_mode !== 'cooperative' || cap.worker_count !== 0
    || cap.queue_capacity !== 8 || cap.retained_results !== 16
    || cap.max_request_bytes !== 65536 || cap.max_entities !== 4096
    || cap.max_trace_entries !== 4096 || cap.max_events !== 32
    || cap.deadline_ms !== 2000 || !equal(cap.supported_domains, expectedDomains)
    || !equal(cap.schemas, expectedAdapterSchemas)) throw new Error('capabilities contract mismatch');
if (manifest.schema_version !== 'procgen-generator-manifest-3'
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
  const accepted = parseLifecycle(binding.generate_bundle_async(JSON.stringify(vector.request)), vector.name);
  if (!equal(accepted.events, ['admitted', 'queued'])) throw new Error(`${vector.name} admission events mismatch`);
  ids.push(BigInt(accepted.request_id));
}
if (ids.join(',') !== '1,2,3,4,5,6,7,8') throw new Error(`queue ids mismatch: ${ids}`);
const overload = parseLifecycle(binding.generate_bundle_async(JSON.stringify(vectors[0].request)), 'overload');
if (overload.request_id !== null || overload.failure?.code !== 'overload'
    || !equal(overload.events, ['rejected', 'overloaded'])) throw new Error('overload contract mismatch');
const recovered = parseLifecycle(binding.poll(ids[0]), 'recovered');
assertBundleContract(recovered.bundle, 'recovered');
if (recovered.bundle?.semantic_hash !== vectors[0].expected_semantic_hash) {
  throw new Error(`queue recovery mismatch: actual=${recovered.bundle?.semantic_hash ?? 'none'} expected=${vectors[0].expected_semantic_hash}`);
}
const cancelled = parseLifecycle(binding.generate_bundle_async(JSON.stringify(vectors[0].request)), 'cancelled');
const cancelId = BigInt(cancelled.request_id);
if (cancelId !== 9n) throw new Error(`recovery id mismatch: ${cancelId}`);
if (parseLifecycle(binding.cancel(cancelId), 'cancel').failure?.code !== 'cancellation') throw new Error('cancel contract mismatch');
if (parseLifecycle(binding.cancel(cancelId), 'cancel idempotence').failure?.code !== 'cancellation') throw new Error('cancel idempotence mismatch');
if (parseLifecycle(binding.poll(cancelId), 'cancel poll').failure?.code !== 'cancellation') throw new Error('cancel poll mismatch');
if (parseLifecycle(binding.poll(cancelId), 'cancel consumption').failure?.code !== 'result_consumed') throw new Error('cancel consumption mismatch');
for (let index = 1; index < ids.length; index += 1) {
  const terminal = parseLifecycle(binding.poll(ids[index]), vectors[index].name);
  if (terminal.bundle?.semantic_hash !== vectors[index].expected_semantic_hash) {
    throw new Error(`${vectors[index].name} queued hash mismatch`);
  }
}
for (const vector of vectors) {
  const raw = JSON.stringify(vector.request);
  const sync = parseLifecycle(binding.generate_bundle(raw), `${vector.name} sync`);
  assertBundleContract(sync.bundle, `${vector.name} sync`);
  if (sync.bundle?.semantic_hash !== vector.expected_semantic_hash) throw new Error(`${vector.name} sync hash mismatch`);
  const accepted = parseLifecycle(binding.generate_bundle_async(raw), `${vector.name} async admission`);
  const id = BigInt(accepted.request_id);
  const terminal = parseLifecycle(binding.poll(id), `${vector.name} async`);
  assertBundleContract(terminal.bundle, `${vector.name} async`);
  if (terminal.bundle?.semantic_hash !== vector.expected_semantic_hash) throw new Error(`${vector.name} async hash mismatch`);
  const consumed = parseLifecycle(binding.poll(id), `${vector.name} consumed`);
  if (consumed.failure?.code !== 'result_consumed') throw new Error(`${vector.name} consumed contract mismatch`);
}
console.log('WASM_LIFECYCLE_SMOKE: PASS');
