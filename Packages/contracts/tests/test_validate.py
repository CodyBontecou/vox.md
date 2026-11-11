import hashlib,json,re,shutil,subprocess,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]; VALIDATOR=Path("Packages/contracts/scripts/validate.py")
class ContractValidatorTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)/"repo"
  trees=("Packages/contracts","Packages/VoxboardShared/Tests/Fixtures/Contracts","Packages/VoxboardShared/Sources/VoxCoreGenerated","Packages/VoxboardShared/Sources/VoxCoreFFI","apps/android/core-bridge/src","apps/android/app/src","apps/android/capture-domain/src","apps/android/data/src","apps/android/data/schemas","apps/android/platform-services/src","apps/android/build-logic","apps/android/gradle","docs/validation","toolchains","Packages/vox-core-rust")
  for rel in trees:
   src=ROOT/rel; dst=self.root/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copytree(src,dst,ignore=shutil.ignore_patterns("__pycache__","target",".build","build",".gradle"))
  (self.root/"docs/architecture").mkdir(parents=True,exist_ok=True)
  for p in (ROOT/"docs/architecture").glob("adr-*.md"): shutil.copyfile(p,self.root/"docs/architecture"/p.name)
  for name in ("android-wear-m1-decisions.md","android-wear-m0-capabilities.json"): shutil.copyfile(ROOT/"docs/architecture"/name,self.root/"docs/architecture"/name)
  for rel in (".github/workflows/contracts-ci.yml",".github/workflows/android-ci.yml","scripts/test-project-contracts.sh","apps/android/build.gradle.kts","apps/android/settings.gradle.kts","apps/android/gradle.properties","apps/android/gradlew","apps/android/gradlew.bat","apps/android/settings-gradle.lockfile","apps/android/scripts/validate-debug-artifacts.py","apps/android/app/build.gradle.kts","apps/android/app/gradle.lockfile","apps/android/core-bridge/build.gradle.kts","apps/android/core-bridge/gradle.lockfile","apps/android/capture-domain/build.gradle.kts","apps/android/capture-domain/gradle.lockfile","apps/android/data/build.gradle.kts","apps/android/data/gradle.lockfile","apps/android/platform-services/build.gradle.kts","apps/android/platform-services/gradle.lockfile"):
   src=ROOT/rel; dst=self.root/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
  for rel in ("Voxboard/Fonts","apps/android/scripts","apps/android/localization","apps/android/wear"):
   src=ROOT/rel; dst=self.root/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copytree(src,dst,ignore=shutil.ignore_patterns("__pycache__","build",".gradle"),dirs_exist_ok=True)
  for rel in ("apps/android/localization-review.json","apps/android/app/proguard-rules.pro"):
   src=ROOT/rel; dst=self.root/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
 def tearDown(self): self.temp.cleanup()
 def run_validator(self): return subprocess.run([sys.executable,str(VALIDATOR),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True)
 def mutate(self,rel,fn):
  p=self.root/rel; v=json.loads(p.read_text()); fn(v); p.write_text(json.dumps(v,indent=2,sort_keys=True)+"\n")
 def rejected(self,result,needle): self.assertNotEqual(result.returncode,0,result.stdout+result.stderr); self.assertIn(needle,result.stdout+result.stderr)
 def test_clean_pass(self): self.assertEqual(self.run_validator().returncode,0)
 def test_android_local_capability_evidence_requires_present_source_symbols(self):
  rel="Packages/contracts/validation/android-local-capability-evidence.json"
  self.mutate(rel,lambda x:x["capabilities"][0]["evidence"][0].update(symbol="missing evidence symbol"))
  self.rejected(self.run_validator(),"capability.acceptanceEvidenceSymbol")
 def test_android_local_capability_evidence_registry_cannot_omit_ledger_claims(self):
  rel="Packages/contracts/validation/android-local-capability-evidence.json"
  self.mutate(rel,lambda x:x["capabilities"].pop())
  self.rejected(self.run_validator(),"capability.acceptanceEvidenceSet")
 def test_android_local_capability_evidence_kind_must_match_ledger(self):
  rel="Packages/contracts/validation/android-local-capability-evidence.json"
  def mismatch(x):
   entry=next(item for item in x["capabilities"] if item["capabilityID"]=="cap.editor.bold")
   entry["acceptanceKinds"]=["fixture"]
  self.mutate(rel,mismatch)
  self.rejected(self.run_validator(),"capability.acceptanceEvidenceKind")
 def test_android_local_ui_evidence_requires_connected_test_gate(self):
  rel="Packages/contracts/validation/android-local-capability-evidence.json"
  def remove_connected_gate(x):
   entry=next(item for item in x["capabilities"] if item["capabilityID"]=="cap.editor.bold")
   entry["gateIDs"]=["android-local-release"]
  self.mutate(rel,remove_connected_gate)
  self.rejected(self.run_validator(),"capability.acceptanceUiGate")
 def test_android_local_ui_evidence_requires_instrumented_source(self):
  rel="Packages/contracts/validation/android-local-capability-evidence.json"
  def remove_instrumented_source(x):
   entry=next(item for item in x["capabilities"] if item["capabilityID"]=="cap.editor.bold")
   entry["evidence"]=[item for item in entry["evidence"] if "/src/androidTest/" not in item["path"]]
  self.mutate(rel,remove_instrumented_source)
  self.rejected(self.run_validator(),"capability.acceptanceUiSource")
 def test_android_local_device_evidence_requires_connected_test_gate(self):
  rel="Packages/contracts/validation/android-local-capability-evidence.json"
  def remove_connected_gate(x):
   entry=next(item for item in x["capabilities"] if item["capabilityID"]=="cap.queue.recovery")
   entry["gateIDs"]=["android-local-release"]
  self.mutate(rel,remove_connected_gate)
  self.rejected(self.run_validator(),"capability.acceptanceDeviceGate")
 def test_android_local_device_evidence_requires_instrumented_source(self):
  rel="Packages/contracts/validation/android-local-capability-evidence.json"
  def remove_instrumented_source(x):
   entry=next(item for item in x["capabilities"] if item["capabilityID"]=="cap.queue.recovery")
   entry["evidence"]=[item for item in entry["evidence"] if "/src/androidTest/" not in item["path"]]
  self.mutate(rel,remove_instrumented_source)
  self.rejected(self.run_validator(),"capability.acceptanceDeviceSource")
 def test_every_capability_whose_milestone_contains_m3_is_exact(self):
  value=json.loads((self.root/"docs/architecture/android-wear-m0-capabilities.json").read_text()); m3={item["id"] for item in value["capabilities"] if "M3" in item["milestone"]}; self.assertEqual(m3,{"cap.ai.mode-none","cap.billing.reinstall-adjustment","cap.delivery.standard","cap.entry.app","cap.history.tombstone","cap.payload.text","cap.payload.url","cap.quota.capture","cap.quota.retry-no-charge","cap.target.new"})
  milestones={item["id"]:item["milestone"] for item in value["capabilities"]}; self.assertEqual(milestones["cap.delivery.voice-meter"],"M4"); self.assertEqual(milestones["cap.quota.transcription"],"M4/M8"); self.assertEqual(milestones["cap.editor.bold"],"M5"); self.assertEqual(milestones["cap.target.daily"],"M5")
  for capability_id in ("cap.preset.audio-save-off","cap.preset.audio-save-alongside","cap.preset.audio-save-attachments","cap.preset.audio-reference-top","cap.preset.audio-reference-bottom"):
   self.assertEqual(milestones[capability_id],"M5/M7")
 def test_contracts_workflow_covers_all_m3_governance_inputs(self):
  workflow=(self.root/".github/workflows/contracts-ci.yml").read_text()
  for trigger in ("apps/android/**","toolchains/**","docs/android-wear-shared-core-implementation-plan.md","docs/architecture/android-wear-m3-scope-and-entry-audit.md","docs/architecture/android-wear-toolchain-baseline.md"):
   self.assertEqual(workflow.count("- '"+trigger+"'"),2,trigger)
 def test_receipt_derivation_vector_is_semantic(self):
  rel="Packages/contracts/fixtures/artifact-plan/valid-receipt-derivation.json"
  self.mutate(rel,lambda x:x.update(receiptID="00000000-0000-4000-8000-000000000000")); self.rejected(self.run_validator(),"receipt.derivation")
 def test_android_package_fixture_bindings_and_fixed_profile_are_semantic(self):
  rel="Packages/contracts/fixtures/android-capture-package/valid-queued-journal.json"
  self.mutate(rel,lambda x:x.update(requestSHA256="f"*64)); self.rejected(self.run_validator(),"package.fixtureBinding")
  self.tearDown();self.setUp();rel="Packages/contracts/fixtures/capture-preparation-input/valid-android-m3-text-link.json"
  def drift_preset(x):
   x["preset"]["id"]="55555555-5555-4555-8555-555555555555"; snapshot=json.loads(json.dumps(x["preset"])); snapshot["snapshotHash"]="0"*64; x["preset"]["snapshotHash"]=hashlib.sha256((json.dumps(snapshot,ensure_ascii=False,indent=2,sort_keys=True)+"\n").encode()).hexdigest()
  self.mutate(rel,drift_preset); self.rejected(self.run_validator(),"package.fixtureProfile")
 def test_schema_unsupported_keyword_rejected(self):
  self.mutate("Packages/contracts/artifact-plan/v1/schema.json",lambda x:x.update(contains={})); self.rejected(self.run_validator(),"schema.unsupportedKeyword")
 def test_typed_negative_expectation_is_enforced(self):
  self.mutate("Packages/contracts/manifest.json",lambda x:x["fixtureCases"][0]["expectedError"].update(code="wrong.code")); self.rejected(self.run_validator(),"fixture.wrongTypedError")
 def test_stale_present_mirror_rejected(self):
  p=self.root/"Packages/VoxboardShared/Tests/Fixtures/Contracts/v1/artifact-plan/v1/contract.md"; p.write_text(p.read_text()+"stale\n"); self.rejected(self.run_validator(),"mirror.bytes")
 def test_declared_m1_resource_mirror_must_be_present(self):
  shutil.rmtree(self.root/"Packages/vox-core-rust/tests/resources/contracts/v1"); self.rejected(self.run_validator(),"mirror.missing")
 def test_required_mirror_without_consumer_rejected(self):
  def f(x): x["mirrors"][0]["lifecycle"]="required"
  self.mutate("Packages/contracts/manifest.json",f); self.rejected(self.run_validator(),"mirror.lifecycle")
 def test_resource_only_cannot_claim_evidence(self):
  def f(x): x["mirrors"][0]["consumer"]="fake"
  self.mutate("Packages/contracts/manifest.json",f); self.rejected(self.run_validator(),"mirror.plannedClaimsEvidence")
 def test_owner_classification_remains_preserved(self):
  self.mutate("Packages/contracts/product-capabilities.json",lambda x:x["capabilities"][0].update(classification="deferred")); self.rejected(self.run_validator(),"capability.conversionDrift")
 def test_acceptance_mapping_mutations_rejected(self):
  rel="Packages/contracts/product-capabilities.json"
  mutations=(lambda x:x["capabilities"][0]["acceptance"][0].update(assertion="changed assertion"),lambda x:x["capabilities"][0]["acceptance"][0].update(path="changed/path"),lambda x:x["capabilities"][0]["acceptance"][0].update(kind="changedKind"),lambda x:x["capabilities"][0]["acceptance"][0].update(status="changedStatus"),lambda x:x["capabilities"][0]["acceptance"][0].update(mappingID="changed.mapping"),lambda x:x["capabilities"][0].update(dependencies=["changed-dependency"]))
  for mutate in mutations:
   with self.subTest(mutate=mutate):
    self.tearDown(); self.setUp(); self.mutate(rel,mutate); self.rejected(self.run_validator(),"capability.conversionDrift")
 def test_unaccepted_scope_variance_rejected(self):
  cid=json.loads((self.root/"Packages/contracts/product-capabilities.json").read_text())["capabilities"][0]["id"]
  v={"capabilityID":cid,"classification":"deferred","decisionID":"PD-M1-NOT-ACCEPTED","reason":"Synthetic scope reason","userVisibleBehavior":"Feature unavailable","objectiveAmended":False,"parityStatus":"blocking"}
  self.mutate("Packages/contracts/scope-variances.json",lambda x:x["variances"].append(v)); self.rejected(self.run_validator(),"variance.unapproved")
 def test_unknown_scope_variance_classification_rejected(self):
  cid=json.loads((self.root/"Packages/contracts/product-capabilities.json").read_text())["capabilities"][0]["id"]
  v={"capabilityID":cid,"classification":"garbage","decisionID":"PD-M1-NOT-ACCEPTED","reason":"Synthetic scope reason","userVisibleBehavior":"Feature unavailable","objectiveAmended":False,"parityStatus":"blocking"}
  self.mutate("Packages/contracts/scope-variances.json",lambda x:x["variances"].append(v)); self.rejected(self.run_validator(),"schema.enum")
 def test_malformed_scope_variance_rejected(self):
  cid=json.loads((self.root/"Packages/contracts/product-capabilities.json").read_text())["capabilities"][0]["id"]
  v={"capabilityID":cid,"classification":"deferred","decisionID":"PD-M1-NOT-ACCEPTED","reason":"Synthetic scope reason","userVisibleBehavior":"Feature unavailable","objectiveAmended":False,"parityStatus":"blocking","unexpected":True}
  self.mutate("Packages/contracts/scope-variances.json",lambda x:x["variances"].append(v)); self.rejected(self.run_validator(),"schema.unknownField")
 def trace_mutation_rejected(self,rel,fn,needle):
  self.mutate(rel,fn);canonical=self.root/rel;suffix=rel.removeprefix("Packages/contracts/")
  for path in ("Packages/VoxboardShared/Tests/Fixtures/Contracts/v1","Packages/vox-core-rust/tests/resources/contracts/v1","apps/android/core-bridge/src/test/resources/contracts/v1"):
   target=self.root/path/suffix; target.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(canonical,target)
  self.rejected(self.run_validator(),needle)
 def test_trace_sequence_mutation_rejected(self):
  self.trace_mutation_rejected("Packages/contracts/fixtures/wearable-protocol-trace/valid-transcript-ingest-commit-delete.json",lambda x:x["events"][5].update(expectedDisposition="duplicateNoOp"),"fixture.validRejected")
 def test_trace_cross_recording_state_rejected(self):
  self.trace_mutation_rejected("Packages/contracts/fixtures/wearable-protocol-trace/valid-transcript-ingest-commit-delete.json",lambda x:x["events"][7]["envelope"].update(recordingID="22222222-2222-4222-8222-222222222222"),"trace.ingestMismatch")
 def test_trace_cross_correlation_state_rejected(self):
  self.trace_mutation_rejected("Packages/contracts/fixtures/wearable-protocol-trace/valid-transcript-ingest-commit-delete.json",lambda x:x["events"][8]["envelope"].update(correlationID="99999999-9999-4999-8999-999999999999"),"trace.commitCorrelation")
 def test_trace_message_id_collision_rejected(self):
  def mutate(x): x["events"][5]["envelope"].update(messageID=x["events"][4]["envelope"]["messageID"])
  self.trace_mutation_rejected("Packages/contracts/fixtures/wearable-protocol-trace/valid-transcript-ingest-commit-delete.json",mutate,"trace.messageIDCollision")
 def test_trace_preset_binding_rejected(self):
  self.trace_mutation_rejected("Packages/contracts/fixtures/wearable-protocol-trace/valid-recording-only.json",lambda x:x["events"][2]["envelope"]["payload"].update(presetSnapshotHash="3"*64),"trace.metadataPresetMismatch")
 def test_trace_frontier_progression_rejected(self):
  self.trace_mutation_rejected("Packages/contracts/fixtures/wearable-protocol-trace/valid-transcript-ingest-commit-delete.json",lambda x:x["events"][5]["envelope"]["payload"].update(frontierRevision=1),"trace.frontierRevision")
 def test_trace_future_retry_rejected(self):
  self.trace_mutation_rejected("Packages/contracts/fixtures/wearable-protocol-trace/valid-reassign-retry.json",lambda x:x["events"][-1]["envelope"]["payload"].update(retryFromRevision=999999),"trace.retryRevision")
 def manifest_error(self,name):
  rel="Packages/contracts/fixtures/wearable-protocol-trace/"+name;case=next(c for c in json.loads((self.root/"Packages/contracts/manifest.json").read_text())["fixtureCases"] if c["path"]==rel);return case["expectedError"]["code"]
 def test_unsupported_version_followup_rejected(self): self.assertEqual(self.manifest_error("invalid-unsupported-followup.json"),"trace.postTerminal")
 def test_trace_envelope_semantics_execute(self):
  self.assertEqual(self.manifest_error("invalid-recording-only-mode-policy.json"),"wear.recordingModePolicy")
  self.assertEqual(self.manifest_error("invalid-transcript-recording-only-policy.json"),"wear.recordingModePolicy")
  self.assertEqual(self.manifest_error("invalid-frontier-exceeds-asset.json"),"wear.frontierBounds")
 def test_asset_replacement_after_ingest_rejected(self): self.assertEqual(self.manifest_error("invalid-asset-replacement-after-ingest.json"),"trace.assetReplacementAfterIngest")
 def test_frozen_policy_reassignment_rejected(self): self.assertEqual(self.manifest_error("invalid-frozen-policy-reassignment.json"),"trace.reassignMeaning")
 def test_reinstall_epoch_is_per_installation(self):
  rel="Packages/contracts/fixtures/wearable-protocol-trace/valid-reinstall-reconciliation.json";x=json.loads((self.root/rel).read_text());self.assertEqual(x["events"][0]["envelope"]["epoch"],100);self.assertEqual(x["events"][2]["envelope"]["epoch"],1);self.assertEqual(x["events"][2]["envelope"]["payload"]["recordings"][0]["lastRevision"],100)
 def test_imported_reconciliation_frontier_blocks_regression_and_terminal_followup(self):
  rel="Packages/contracts/fixtures/wearable-protocol-trace/valid-reinstall-reconciliation.json"
  def f(x):
   imported=x["events"][2];imported["envelope"]["payload"]["recordings"][0]["state"]="terminalFailure"
   follow=copy.deepcopy(x["events"][0]);follow["envelope"].update(senderInstallationID=imported["envelope"]["senderInstallationID"],deviceID=imported["envelope"]["deviceID"],recordingID=imported["envelope"]["recordingID"],epoch=imported["envelope"]["epoch"],correlationID=imported["envelope"]["correlationID"],messageID="eeeeeee1-1111-4111-8111-111111111111",revision=101);follow["expectedDisposition"]="accepted";x["events"].append(follow)
  import copy
  self.trace_mutation_rejected(rel,f,"trace.postTerminal")
 def test_secondary_imported_terminal_frontier_blocks_followup(self):
  rel="Packages/contracts/fixtures/wearable-protocol-trace/valid-reinstall-reconciliation.json"
  def f(x):
   imported=x["events"][2];secondary="22222222-2222-4222-8222-222222222222";imported["envelope"]["payload"]["recordings"].append({"recordingID":secondary,"lastRevision":100,"state":"terminalFailure"})
   follow=copy.deepcopy(x["events"][0]);follow["envelope"].update(senderInstallationID=imported["envelope"]["senderInstallationID"],deviceID=imported["envelope"]["deviceID"],recordingID=secondary,epoch=imported["envelope"]["epoch"],correlationID=imported["envelope"]["correlationID"],messageID="eeeeeee2-1111-4111-8111-111111111111",revision=101);follow["expectedDisposition"]="accepted";x["events"].append(follow)
  import copy
  self.trace_mutation_rejected(rel,f,"trace.postTerminal")
 def test_retired_installation_switchback_rejected(self):
  rel="Packages/contracts/fixtures/wearable-protocol-trace/valid-reinstall-reconciliation.json"
  def f(x):
   old=copy.deepcopy(x["events"][0]);old["envelope"].update(messageKind="reconciliationSummary",messageID="ddddddd1-1111-4111-8111-111111111111",epoch=101,revision=1);old["envelope"]["payload"]={"pendingActionCorrelationIDs":[],"recordings":[{"lastRevision":1,"recordingID":old["envelope"]["recordingID"],"state":"localRecorded"}]};old["envelope"]["replayRule"]="newerRevisionWins";old["expectedDisposition"]="accepted";x["events"].append(old);x["expectedFinalRecordingIdentity"]={k:old["envelope"][k] for k in ("senderInstallationID","deviceID","recordingID","epoch","correlationID")}
  import copy
  self.trace_mutation_rejected(rel,f,"trace.dispositionMismatch")
 def test_reconciliation_payload_mutations_rejected(self):
  rel="Packages/contracts/fixtures/wearable-protocol-trace/valid-negotiation-preset-reconciliation.json"
  mutations=(lambda x:x["events"][-1]["envelope"]["payload"]["recordings"][0].update(recordingID="22222222-2222-4222-8222-222222222222"),lambda x:x["events"][-1]["envelope"]["payload"]["recordings"].append(dict(x["events"][-1]["envelope"]["payload"]["recordings"][0])),lambda x:x["events"][-1]["envelope"]["payload"]["recordings"][0].update(lastRevision=99),lambda x:x["events"][-1]["envelope"]["payload"]["recordings"][0].update(state="vaultCommitted"),lambda x:x["events"][-1]["envelope"]["payload"]["pendingActionCorrelationIDs"].append("77777777-7777-4777-8777-777777777777"))
  for mutate in mutations:
   with self.subTest(mutate=mutate):
    self.tearDown();self.setUp();self.trace_mutation_rejected(rel,mutate,"fixture.validRejected")
 def test_rejected_and_stale_message_id_reuse_rejected(self):
  for index in (1,3):
   with self.subTest(index=index):
    self.tearDown();self.setUp();rel="Packages/contracts/fixtures/wearable-protocol-trace/valid-reinstall-reconciliation.json"
    def f(x,index=index): changed=copy.deepcopy(x["events"][index]);changed["envelope"]["revision"]+=10;changed["expectedDisposition"]="foreignInstallationRejected";x["events"].append(changed)
    import copy
    self.trace_mutation_rejected(rel,f,"trace.messageIDCollision")
 def test_core_api_semantic_negatives_are_typed(self):
  cases=json.loads((self.root/"Packages/contracts/manifest.json").read_text())["fixtureCases"]
  errors={Path(c["path"]).name:c.get("expectedError",{}).get("code") for c in cases if c["family"]=="core-api"}
  self.assertEqual(errors["invalid-ready-not-permitted.json"],"core.readinessCoherence")
  self.assertEqual(errors["invalid-incompatible-no-mismatch.json"],"core.readinessCoherence")
  self.assertEqual(errors["invalid-descriptor-order.json"],"core.descriptorOrder")
  self.assertEqual(errors["invalid-duplicate-drained-artifact.json"],"core.duplicateDrainedArtifact")
 def test_artifact_identity_mutations_rejected(self):
  rel="Packages/contracts/fixtures/artifact-plan/valid-complete.json"
  for field,code in (("operationID","plan.operationID"),("artifactID","plan.artifactID"),("preparedStreamID","plan.streamID")):
   with self.subTest(field=field):
    self.tearDown();self.setUp()
    def f(x,field=field): x["artifacts"][-1][field]="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    self.trace_mutation_rejected(rel,f,code)
 def test_artifact_plan_hash_mutation_rejected(self):
  self.trace_mutation_rejected("Packages/contracts/fixtures/artifact-plan/valid-complete.json",lambda x:x.update(planHash="f"*64),"plan.hash")
 def test_toolchain_validator_rejects_pin_and_binding_inventory_drift(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py"
  p=self.root/"toolchains/android-wear-shared-core.json";m=json.loads(p.read_text());m["rust"]["toolchain"]="stable";p.write_text(json.dumps(m,indent=2,sort_keys=True)+"\n")
  r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.assertNotEqual(r.returncode,0)
  self.tearDown();self.setUp();(self.root/"Packages/vox-core-rust/generated/swift/VoxCore.swift").unlink();r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.assertNotEqual(r.returncode,0);self.assertIn("generated binding missing",r.stderr+r.stdout)
  self.tearDown();self.setUp();p=self.root/"toolchains/android-wear-shared-core.json";m=json.loads(p.read_text());m["androidApplication"]["sdk"]["compileSdk"]=36;p.write_text(json.dumps(m,indent=2,sort_keys=True)+"\n");r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.assertNotEqual(r.returncode,0);self.assertIn("Android application pins differ",r.stderr+r.stdout)
  self.tearDown();self.setUp();p=self.root/"apps/android/gradle/libs.versions.toml";p.write_text(p.read_text().replace('room = "2.8.4"','room = "2.8.3"'));r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.assertNotEqual(r.returncode,0);self.assertIn("Android version catalog pins differ",r.stderr+r.stdout)
  self.tearDown();self.setUp();p=self.root/"apps/android/gradle/wrapper/gradle-wrapper.jar";p.write_bytes(p.read_bytes()+b"\0");r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.assertNotEqual(r.returncode,0);self.assertIn("Gradle wrapper JAR drift",r.stderr+r.stdout)
 def test_governed_ci_actions_require_immutable_revisions(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py"; rel=".github/workflows/contracts-ci.yml"; p=self.root/rel; p.write_text(p.read_text().replace("actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd", "actions/checkout@v6")); r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True); self.rejected(r,"Contracts CI action is not immutable")
 def test_android_phase4_bridge_policy_mutations_are_rejected(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py"
  for rel,old,new,needle in (("Packages/vox-core-rust/uniffi.toml","android_cleaner = true","android_cleaner = false","Android-safe UniFFI cleaner configuration drift"),("Packages/vox-core-rust/generated/kotlin/md/vox/core/vox_core_uniffi.kt","internal fun `corePrepare`","fun `corePrepare`","generated Kotlin module-internal surface drift"),("apps/android/core-bridge/build.gradle.kts","generated/vox-native/debug/jniLibs","generated/vox-native/shared/jniLibs","Android Phase 4 native packaging drift"),("apps/android/core-bridge/src/main/kotlin/md/vox/android/corebridge/GeneratedNativeCoreAdapter.kt","withOwnedDirectBytes(bytes) { corePrepare(it) }","corePrepare(ByteBuffer.wrap(bytes))","wraps caller-owned heap buffers"),("apps/android/app/src/main/kotlin/md/vox/android/VoxApplication.kt","productionCoreBridge()","unwiredCoreBridge()","wires the unwired core bridge")):
   with self.subTest(path=rel):
    self.tearDown(); self.setUp(); p=self.root/rel; p.write_text(p.read_text().replace(old,new)); r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True); self.rejected(r,needle)
 def test_android_phase4_generated_binding_bypass_sources_are_rejected(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py"
  for source_set in ("debug", "release", "paid"):
   with self.subTest(source_set=source_set):
    self.tearDown(); self.setUp(); p=self.root/f"apps/android/app/src/{source_set}/java/md/vox/android/GeneratedBypass.java"; p.parent.mkdir(parents=True,exist_ok=True); p.write_text("final class GeneratedBypass { Object call() { return md.vox.core.Vox_core_uniffiKt.coreBuildInfo(); } }\n"); r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True); self.rejected(r,"production source bypasses the handwritten core bridge")
 def test_android_phase4_generated_enum_surface_is_rejected(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py"; rel="Packages/vox-core-rust/generated/kotlin/md/vox/core/vox_core_uniffi.kt"; p=self.root/rel; p.write_text(p.read_text()+"\nenum class FutureGeneratedEnum { VALUE }\n"); r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True); self.rejected(r,"generated Kotlin exposes a public top-level declaration")
 def test_kotlin_binding_normalizer_internalizes_future_enum_shape(self):
  rel="Packages/vox-core-rust/generated/kotlin/md/vox/core/vox_core_uniffi.kt"; p=self.root/rel; text=p.read_text().replace("internal ",""); text=re.sub(r"if \(\(lib\.(uniffi_[A-Za-z0-9_]+_checksum_[A-Za-z0-9_]+)\(\) and 0xffff\) != ([0-9]+)\) \{",r"if (lib.\1() != \2) {",text); p.write_text(text+"\nenum class FutureGeneratedEnum { VALUE }\nannotation class FutureGeneratedAnnotation\nvalue class FutureGeneratedValue(val raw: Int)\nfun interface FutureGeneratedCallback { fun call() }\n"); script=self.root/"Packages/vox-core-rust/scripts/normalize-kotlin-bindings.py"; r=subprocess.run([sys.executable,str(script),str(p.parents[3])],cwd=self.root,text=True,capture_output=True); self.assertEqual(r.returncode,0,r.stdout+r.stderr); normalized=p.read_text(); self.assertIn("internal enum class FutureGeneratedEnum",normalized); self.assertIn("internal annotation class FutureGeneratedAnnotation",normalized); self.assertIn("internal value class FutureGeneratedValue",normalized); self.assertIn("internal fun interface FutureGeneratedCallback",normalized)
 def test_android_aapt2_linux_verification_metadata_is_exact(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py";rel="apps/android/gradle/verification-metadata.xml"
  linux='''         <artifact name="aapt2-9.1.1-14792394-linux.jar">\n            <sha256 value="e7ae17af6e4093c771243e82d66462353de87befaac206bfb43e557ac1c34440" origin="Manually verified from pinned Google Maven URL"/>\n         </artifact>\n'''
  mutations=(lambda text:text.replace(linux,""),lambda text:text.replace("e7ae17af6e4093c771243e82d66462353de87befaac206bfb43e557ac1c34440","f"*64),lambda text:text.replace("Manually verified from pinned Google Maven URL","Generated by Gradle"))
  for mutate in mutations:
   with self.subTest(mutate=mutate):
    self.tearDown();self.setUp();p=self.root/rel;p.write_text(mutate(p.read_text()));r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.rejected(r,"AAPT2 artifact missing/drifted")
 def test_android_linux_resolved_verification_metadata_is_exact(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py";rel="apps/android/gradle/verification-metadata.xml"
  checksums=("1239e9dbe1397cd5971342956b2511bc3ace7b641842e4372a088dcfa8b9ad55","55441db27e8869dfefe053059bdf478bdc7e95585642bf391f0023345fd56287","de23b114b3e4119a8fe6eb17bed5a3852816698bace67071579d6d927ebb080a","86477abcf490d6ca059aa9973cb108d22a506f49d1a5569bb32cc6cbf43c2cce","ab137ba5a8e32c9b066bf9126a1c76dd5614b724ba5c0b02549772b5e9f4cf1f")
  for checksum in checksums:
   with self.subTest(checksum=checksum):
    self.tearDown();self.setUp();p=self.root/rel;p.write_text(p.read_text().replace(checksum,"f"*64));r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.rejected(r,"Linux-resolved")
 def test_android_dependency_metadata_path_inventory_is_exact(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py";p=self.root/"toolchains/android-wear-shared-core.json";m=json.loads(p.read_text());m["androidApplication"]["dependencyMetadataPaths"]["moduleLocks"].pop();p.write_text(json.dumps(m,indent=2,sort_keys=True)+"\n");r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.rejected(r,"Android application pins differ")
 def test_android_command_line_tools_pin_is_exact(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py";p=self.root/"toolchains/android-wear-shared-core.json";m=json.loads(p.read_text());m["androidApplication"]["androidCommandLineTools"]["toolsVersion"]="latest";p.write_text(json.dumps(m,indent=2,sort_keys=True)+"\n");r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.rejected(r,"Android application pins differ")
 def test_android_module_graph_rejects_extra_reverse_and_cycle_edges(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py"
  mutations=(("apps/android/app/build.gradle.kts",'implementation(project(":wear"))'),("apps/android/core-bridge/build.gradle.kts",'implementation(project(":app"))'),("apps/android/platform-services/build.gradle.kts",'implementation(project(":app"))'))
  for rel,edge in mutations:
   with self.subTest(path=rel,edge=edge):
    self.tearDown();self.setUp();p=self.root/rel;p.write_text(p.read_text()+"\ndependencies { "+edge+" }\n");r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.rejected(r,"Android module graph differs")
 def test_android_framework_runtime_activation_is_rejected(self):
  validator=ROOT/"Packages/contracts/scripts/validate_toolchain.py";rel="apps/android/data/build.gradle.kts";p=self.root/rel;p.write_text(p.read_text().replace("compileOnly(libs.work.runtime.ktx)","implementation(libs.work.runtime.ktx)"));r=subprocess.run([sys.executable,str(validator),"--root",str(self.root)],cwd=self.root,text=True,capture_output=True);self.rejected(r,"must remain compileOnly")
 def test_all_wearable_integers_are_bounded(self):
  schema=json.loads((self.root/"Packages/contracts/wearable-protocol/v1/schema.json").read_text());missing=[]
  def walk(v,path="$"):
   if isinstance(v,dict):
    if v.get("type")=="integer" and "const" not in v and "maximum" not in v: missing.append(path)
    for k,z in v.items(): walk(z,path+"."+k)
   elif isinstance(v,list):
    for i,z in enumerate(v): walk(z,f"{path}[{i}]")
  walk(schema);self.assertEqual(missing,[])
if __name__=="__main__": unittest.main()
