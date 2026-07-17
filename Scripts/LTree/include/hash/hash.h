/* hash.h -- unified hashing API for -o HASH / -o DIFF / --save-output.
 *
 * Two algorithms, both implemented from scratch (no external deps,
 * matching the rest of the project):
 *
 *   HASH_ALGO_FAST   xxHash64  -- 8-byte digest, streaming-friendly,
 *                     non-cryptographic. This is the default: for
 *                     change detection you want raw throughput, and a
 *                     64-bit digest is already astronomically
 *                     collision-safe for "did this file change"
 *                     purposes.
 *   HASH_ALGO_CRYPTO SHA-256  -- 32-byte digest, collision-resistant,
 *                     used when --cryptographic is passed, for anyone
 *                     who wants to actually trust the hash for
 *                     integrity rather than just drift detection.
 */
#ifndef LTREE_HASH_H
#define LTREE_HASH_H

#include <stddef.h>
#include <stdint.h>
#include "core/config.h"

#define HASH_MAX_BYTES 32   /* SHA-256 digest size; xxHash64 uses the first 8 */

/* Digest size in bytes for a given algorithm (8 or 32). 0 for NONE. */
size_t hash_digest_size(HashAlgo algo);

/* Human name, e.g. "xxhash64" / "sha256" -- also used as the
 * "hash_algo" field in saved JSON snapshots. */
const char *hash_algo_name(HashAlgo algo);

/* Parse the JSON "hash_algo" string back into a HashAlgo. Returns
 * HASH_ALGO_NONE for anything unrecognised. */
HashAlgo hash_algo_from_name(const char *name);

/* Hash a single contiguous buffer (e.g. an mmap'd file). Writes up to
 * HASH_MAX_BYTES into out and sets *out_len to the digest size. */
void hash_compute(HashAlgo algo, const void *data, size_t len,
                   uint8_t out[HASH_MAX_BYTES], uint8_t *out_len);

/* Combine a directory's direct children into one digest, order-stable
 * (children are already sorted by name by the time this is called).
 * Feeds "<name>\0<hash bytes>" for each child through the same
 * algorithm -- so a directory's hash changes iff a child's name or
 * hash changes. No file re-reading involved, just already-computed
 * child digests. */
void hash_combine_children(HashAlgo algo,
                            char **names, uint8_t (*hashes)[HASH_MAX_BYTES],
                            uint8_t *hash_lens, size_t n,
                            uint8_t out[HASH_MAX_BYTES], uint8_t *out_len);

#endif
