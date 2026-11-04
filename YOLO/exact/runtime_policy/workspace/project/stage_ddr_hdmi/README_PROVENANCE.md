# Source provenance

`sources_pango.f`, `board/vendor_sources.f`, the explicit S3 board RTL files,
`coremark-itcm.mem`, `coremark-dtcm.mem`, the board FDC and the DDR RCF form the
production source set. Their individual hashes and combined identity are in
`project/pds_s3_npu175_functional/launch.json` at the candidate root.

This directory was copied from a stage170-derived S3 staging tree. Files such
as `binding_audit.json`, `staging.json`, `CPU_WB_LOCAL_PROBE.json`, and
`monitor_host_test_status.json` are inherited baseline records. They are kept
for traceability, not evidence that the new 175 MHz S3 variant passed a test.
Use the new PDS summary and `evidence/s3_board_*_175_*` logs for this variant.

The new `source_identity.json` identifies the functional 175 MHz variant.
External model assets are managed separately in
`model/vision5mp_s3_v2_palm_candidate_20260929` and are not embedded in this
source tree.
