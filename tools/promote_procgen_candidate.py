#!/usr/bin/env python3
"""Validate and atomically promote reviewed seed-lab candidates."""
from __future__ import annotations
import argparse, hashlib, json, os, re, subprocess, tempfile
from pathlib import Path
from typing import Any
MAX_BYTES=64*1024; MAX_CORPUS_BYTES=8*1024*1024; MAX_ENTRIES=4096; MAX_DEPTH=12; MAX_COLLECTION=64
CLASSIFICATIONS={"approved_candidate","failure_seed","authored_fallback"}; DOMAINS=["world","site","gameplay","presentation"]; ARCHETYPES={"shuttle","frigate","corvette","freighter"}; DIFFICULTIES={"standard","deep_dive","hardened"}; SIGNALS={"combat_mastery","damage_pressure","resource_pressure","objective_pace"}
CODE=re.compile(r"^[a-z0-9_.:-]{1,128}$"); FALLBACK=re.compile(r"^(?:[a-z0-9_.:-]+|world:[a-z0-9_.:-]+\|site:[a-z0-9_.:-]+)$"); HEX64=re.compile(r"^[a-f0-9]{64}$"); HEX40=re.compile(r"^[a-f0-9]{40}$"); APPROVAL=re.compile(r"^synaptic-sea-stage-gate:t_[a-z0-9]+$"); LOCALES=re.compile(r"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$")
DENY={"username","user_name","account_id","machine","hostname","path","filesystem_path","notes","model","model_output","network","stack_trace","personal_data","device_id"}
def _canonical(v:Any)->bytes:return json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()
def candidate_id_for(c:str,i:str)->str:return hashlib.sha256(f"{c}:{i}".encode("ascii")).hexdigest()
def _fail(s:str)->None:raise ValueError(s)
def _walk(v:Any,d=0,w="candidate"):
    if d>MAX_DEPTH:_fail("nested value exceeds depth cap")
    if isinstance(v,dict):
        if len(v)>MAX_COLLECTION:_fail(f"dictionary exceeds cap: {w}")
        for k,x in v.items():
            if not isinstance(k,str) or len(k.encode())>128 or k.casefold() in DENY:_fail(f"privacy or key violation: {w}.{k}")
            _walk(x,d+1,f"{w}.{k}")
    elif isinstance(v,list):
        if len(v)>MAX_COLLECTION:_fail(f"list exceeds cap: {w}")
        for i,x in enumerate(v):_walk(x,d+1,f"{w}[{i}]")
    elif isinstance(v,str) and len(v.encode())>128:_fail(f"string exceeds cap: {w}")
def _identities(root:Path):
    ms=[json.loads((root/"data/procgen/manifests/build"/n).read_text()) for n in ("win64.json","web.json")]
    if any(m.get("manifest_schema")!="procgen-build-manifest-4" for m in ms):_fail("unsupported build manifest schema")
    vals=[(m.get("rust_source_commit"),m.get("content_manifest_hash"),m.get("generator_version"),m.get("export_schemas")) for m in ms]
    if vals[0]!=vals[1]:_fail("Windows/Web build manifests disagree")
    source,content,generator,_=vals[0]
    if not HEX40.fullmatch(source or "") or not HEX64.fullmatch(content or "") or generator!=3:_fail("invalid manifest identity")
    arts={}
    for m in ms:
        a=m.get("artifact",{}); target=m.get("target")
        if not HEX64.fullmatch(a.get("sha256","")): _fail("invalid artifact identity")
        arts[target]=a["sha256"]
    return content,source,arts
def _validate_request(r:Any,h:str):
    keys={"schema_version","world_seed","site","difficulty_id","player_model","requested_domains","presentation","generator_version","content_manifest_hash"}
    if not isinstance(r,dict) or set(r)!=keys or r["schema_version"]!="procgen-request-2" or r["generator_version"]!=3 or r["content_manifest_hash"]!=h:_fail("request contract")
    domains=r["requested_domains"]
    if not isinstance(r["world_seed"],int) or not 0<=r["world_seed"]<=9007199254740991 or r["difficulty_id"] not in DIFFICULTIES:_fail("request seed/difficulty")
    if not isinstance(domains,list) or not 1<=len(domains)<=len(DOMAINS) or len(domains)!=len(set(domains)) or any(x not in DOMAINS for x in domains) or domains!=[x for x in DOMAINS if x in domains]:_fail("request domains")
    s=r["site"]; sk={"site_id","x","y","archetype_id","kit_id","intactness_override_bp","cause_of_loss","loot_richness_bp"}
    if not isinstance(s,dict) or set(s)!=sk or not isinstance(s["site_id"],str) or not s["site_id"] or s["kit_id"] != "ship_structural_v0" or s["archetype_id"] not in ARCHETYPES:_fail("site contract")
    if not all(isinstance(s[k],int) and -(2**31)<=s[k]<=2**31-1 for k in ("x","y")) or not isinstance(s["loot_richness_bp"],int) or not 0<=s["loot_richness_bp"]<=30000:_fail("site bounds")
    if s["intactness_override_bp"] is not None and (not isinstance(s["intactness_override_bp"],int) or not 0<=s["intactness_override_bp"]<=10000):_fail("intactness bound")
    if s["cause_of_loss"] is not None and s["cause_of_loss"] not in {"ReactorBreach","Depressurization","PirateBoarding","Plague","DriveMisjump","Unknown"}:_fail("cause of loss")
    p=r["player_model"]
    if not isinstance(p,dict) or set(p)!={"schema_version","signals"} or p["schema_version"]!="player-model-2" or not isinstance(p["signals"],list) or len(p["signals"])>MAX_COLLECTION:_fail("player model")
    for x in p["signals"]:
        if not isinstance(x,dict) or set(x)!={"kind","value_bp"} or x["kind"] not in SIGNALS or not isinstance(x["value_bp"],int) or not 0<=x["value_bp"]<=10000:_fail("player signal")
    q=r["presentation"]
    if not isinstance(q,dict) or set(q)!={"seed","locale"} or not isinstance(q["seed"],int) or not 0<=q["seed"]<=9007199254740991 or not isinstance(q["locale"],str) or not LOCALES.fullmatch(q["locale"]):_fail("presentation")
def validate_candidate(c:Any,root:Path,*,promoted=False):
    base={"schema_version","candidate_id","classification","request","expected","source_diagnostic","provenance"}; allowed=base|({"approval_ref"} if promoted else set())
    if not isinstance(c,dict) or set(c)!=allowed or c.get("schema_version")!="procgen-promotion-candidate-1":_fail("candidate keys")
    _walk(c); cl=c["classification"]
    if cl not in CLASSIFICATIONS:_fail("classification")
    if promoted and (not isinstance(c.get("approval_ref"),str) or not APPROVAL.fullmatch(c["approval_ref"])): _fail("approval reference")
    d=c["source_diagnostic"]
    if not isinstance(d,dict) or set(d)!={"identity_hash","capture_hash"} or not HEX64.fullmatch(d.get("identity_hash","")) or not HEX64.fullmatch(d.get("capture_hash","")):_fail("diagnostic hashes")
    if c["candidate_id"]!=candidate_id_for(cl,d["identity_hash"]):_fail("candidate id")
    h,source,arts=_identities(Path(root).resolve()); p=c["provenance"]; pk={"tool_version","generator_version","content_manifest_hash","rust_source_commit","build_target","artifact_sha256","technical_validation_codes"}
    if not isinstance(p,dict) or set(p)!=pk or p.get("tool_version")!="seed-lab-1" or p.get("generator_version")!=3 or p.get("content_manifest_hash")!=h or p.get("rust_source_commit")!=source:_fail("provenance identity")
    if p.get("build_target") not in arts or p.get("artifact_sha256")!=arts[p["build_target"]]:_fail("artifact identity")
    codes=p.get("technical_validation_codes")
    if not isinstance(codes,list) or codes!=sorted(set(codes)) or not all(isinstance(x,str) and CODE.fullmatch(x) for x in codes):_fail("technical validation codes")
    _validate_request(c["request"],h); e=c["expected"]
    if not isinstance(e,dict) or set(e)!={"semantic_hash","failure_code","fallback_id","trace_code"}:_fail("expected keys")
    if e["semantic_hash"] is not None and (not isinstance(e["semantic_hash"],str) or not HEX64.fullmatch(e["semantic_hash"] )):_fail("semantic hash")
    for k in ("failure_code","trace_code"):
        if e[k] is not None and (not isinstance(e[k],str) or not CODE.fullmatch(e[k])):_fail(k)
    if e["fallback_id"] is not None and (not isinstance(e["fallback_id"],str) or len(e["fallback_id"].encode())>128 or not FALLBACK.fullmatch(e["fallback_id"])):_fail("fallback_id")
    if cl=="approved_candidate" and (e["semantic_hash"] is None or e["failure_code"] is not None or e["fallback_id"] is not None or e["trace_code"] is not None):_fail("approved evidence")
    if cl=="failure_seed" and e["fallback_id"] is not None or cl=="failure_seed" and e["semantic_hash"] is None and e["failure_code"] is None:_fail("failure evidence")
    if cl=="authored_fallback" and (e["semantic_hash"] is None or e["fallback_id"] is None or e["failure_code"] is not None or e["trace_code"]!="site:selected_fallback"):_fail("fallback evidence")
    if len(_canonical(c))>MAX_BYTES:_fail("candidate exceeds 64 KiB")
    return c
def _load(p:Path):return json.loads(p.read_text(encoding="utf-8"))
def _write_atomic(p:Path,v:Any):
    p.parent.mkdir(parents=True,exist_ok=True); fd,t=tempfile.mkstemp(prefix=f".{p.name}.",suffix=".tmp",dir=p.parent)
    try:
        with os.fdopen(fd,"w",encoding="utf-8",newline="\n") as f:json.dump(v,f,sort_keys=True,indent=2,ensure_ascii=False); f.write("\n")
        os.replace(t,p)
    finally:
        if os.path.exists(t):os.unlink(t)
def promote_candidate(candidate_path:Path|None,corpus_path:Path,root:Path,*,approval_ref:str|None=None,dry_run=False,check=False):
    if corpus_path.exists() and corpus_path.stat().st_size>MAX_CORPUS_BYTES:_fail("corpus exceeds byte cap")
    corpus=_load(corpus_path) if corpus_path.exists() else {"schema_version":"procgen-regression-corpus-1","entries":[]}
    if set(corpus)!={"schema_version","entries"} or corpus["schema_version"]!="procgen-regression-corpus-1" or not isinstance(corpus["entries"],list) or len(corpus["entries"])>MAX_ENTRIES:_fail("corpus schema/cap")
    entries=[validate_candidate(x,root,promoted=True) for x in corpus["entries"]]; ids=[x["candidate_id"] for x in entries]
    if ids!=sorted(ids) or len(ids)!=len(set(ids)):_fail("corpus ordering/duplicate")
    if candidate_path is not None:
        if candidate_path.stat().st_size>MAX_BYTES:_fail("candidate exceeds 64 KiB")
        if not approval_ref or not APPROVAL.fullmatch(approval_ref):_fail("approval reference required")
        x=validate_candidate(_load(candidate_path),root); x["approval_ref"]=approval_ref; validate_candidate(x,root,promoted=True)
        if x["candidate_id"] in ids:_fail("duplicate candidate")
        entries.append(x); entries.sort(key=lambda v:v["candidate_id"])
        if len(entries)>MAX_ENTRIES:_fail("corpus entry cap")
    proposed={"schema_version":"procgen-regression-corpus-1","entries":entries}
    if len(_canonical(proposed))>MAX_CORPUS_BYTES:_fail("corpus exceeds byte cap")
    if check or dry_run:return True
    _write_atomic(corpus_path,proposed); return True
def main()->int:
    p=argparse.ArgumentParser(); p.add_argument("--candidate",type=Path); p.add_argument("--corpus",type=Path,required=True); p.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[1]); p.add_argument("--approval-ref"); p.add_argument("--dry-run",action="store_true"); p.add_argument("--check",action="store_true"); a=p.parse_args()
    if a.candidate is None and a.approval_ref:p.error("--approval-ref requires --candidate")
    promote_candidate(a.candidate,a.corpus,a.root,approval_ref=a.approval_ref,dry_run=a.dry_run,check=a.check); n=len(_load(a.corpus)["entries"]) if a.corpus.exists() else 0; print(f"PROCGEN PROMOTION CORPUS PASS entries={n}"); return 0
if __name__=="__main__":raise SystemExit(main())
