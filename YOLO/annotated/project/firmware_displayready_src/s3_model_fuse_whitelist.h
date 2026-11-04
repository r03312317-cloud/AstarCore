#ifndef SOC_S3_MODEL_FUSE_WHITELIST_H
#define SOC_S3_MODEL_FUSE_WHITELIST_H

/* Exact stage170 V2 candidate descriptor batches. The 57 Requant->LUT
 * intermediate buffers have no reader before their next write, including
 * across batch boundaries. Generated from manifest assets with CRC32; only
 * these immutable descriptor bytes may use the fused output destination.
 * A different model or rebatch uses hardware Requant without LUT fusion. */
typedef struct { uint32_t base,count,crc32; } soc_s3_fuse_batch;
static const soc_s3_fuse_batch soc_s3_fuse_batches[13]={
 {0x80587300u,16u,0x87150c74u},
 {0x80587900u,16u,0xd33726b9u},
 {0x80587f00u,16u,0x97de2c04u},
 {0x80588500u,16u,0x1e2fb6b4u},
 {0x80588b00u,16u,0xa13fd876u},
 {0x80589100u,16u,0xb4f39381u},
 {0x80589700u,16u,0xb7383d20u},
 {0x80589d00u,16u,0x0a9a600fu},
 {0x8058a300u,16u,0x12dbba0cu},
 {0x8058a900u,16u,0xf90b63e6u},
 {0x8058af00u,16u,0xbc68499fu},
 {0x8058b500u,16u,0x76451b70u},
 {0x8058bb00u,12u,0x64744f4au}
};
/* One contiguous 204-descriptor submission, generated from the same 13
 * immutable assets. CRC32 is over all 19,584 descriptor bytes in order. */
static const soc_s3_fuse_batch soc_s3_fuse_full_graph={
 0x80587300u,204u,0x54764721u
};
#endif
