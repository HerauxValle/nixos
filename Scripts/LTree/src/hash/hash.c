/* &desc: "Implements xxHash64 and SHA-256 from the published reference constants (no external hashing library) behind one hash_compute dispatch function, plus hash_combine_children for directory digests." */
#define _GNU_SOURCE
/* hash.c -- see hash.h.
 *
 * Both algorithms below are well-known, publicly documented
 * constructions (xxHash by Yann Collet, SHA-256 per FIPS 180-4),
 * implemented here from the published specification/reference
 * constants so the binary has zero external hashing dependency.
 *
 * Endianness note: both read little-endian words directly out of the
 * mmap'd byte stream via memcpy (never through an aligned pointer
 * cast, to stay UB-free on strict-alignment targets). This project
 * only ships for Linux/glibc/musl on mainstream (little-endian)
 * targets per the flake, so we don't carry a byte-swap path for
 * big-endian hosts -- documented as a known limitation rather than
 * dead code nobody can test.
 */
#include "hash/hash.h"
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

/* ===================== dispatch / metadata ============================ */
size_t hash_digest_size(HashAlgo algo) {
    switch (algo) {
        case HASH_ALGO_FAST:   return 8;
        case HASH_ALGO_CRYPTO: return 32;
        default:                return 0;
    }
}

const char *hash_algo_name(HashAlgo algo) {
    switch (algo) {
        case HASH_ALGO_FAST:   return "xxhash64";
        case HASH_ALGO_CRYPTO: return "sha256";
        default:                return "none";
    }
}

HashAlgo hash_algo_from_name(const char *name) {
    if (!name) return HASH_ALGO_NONE;
    if (strcmp(name, "xxhash64") == 0) return HASH_ALGO_FAST;
    if (strcmp(name, "sha256") == 0)   return HASH_ALGO_CRYPTO;
    return HASH_ALGO_NONE;
}

/* ===================== xxHash64 (reference algorithm) ================= */
static const uint64_t XXH_P1 = 11400714785074694791ULL;
static const uint64_t XXH_P2 = 14029467366897019727ULL;
static const uint64_t XXH_P3 = 1609587929392839161ULL;
static const uint64_t XXH_P4 = 9650029242287828579ULL;
static const uint64_t XXH_P5 = 2870177450012600261ULL;

static inline uint64_t xxh_rotl64(uint64_t x, int r) {
    return (x << r) | (x >> (64 - r));
}

static inline uint64_t xxh_read64(const uint8_t *p) {
    uint64_t v;
    memcpy(&v, p, 8);
    return v; /* assumes little-endian host, see file header note */
}

static inline uint32_t xxh_read32(const uint8_t *p) {
    uint32_t v;
    memcpy(&v, p, 4);
    return v;
}

static inline uint64_t xxh_round(uint64_t acc, uint64_t input) {
    acc += input * XXH_P2;
    acc = xxh_rotl64(acc, 31);
    acc *= XXH_P1;
    return acc;
}

static inline uint64_t xxh_mergeround(uint64_t acc, uint64_t val) {
    val = xxh_round(0, val);
    acc ^= val;
    acc = acc * XXH_P1 + XXH_P4;
    return acc;
}

static uint64_t xxh64(const void *input, size_t len, uint64_t seed) {
    const uint8_t *p = (const uint8_t *)input;
    const uint8_t *end = p + len;
    uint64_t h64;

    if (len >= 32) {
        const uint8_t *limit = end - 32;
        uint64_t v1 = seed + XXH_P1 + XXH_P2;
        uint64_t v2 = seed + XXH_P2;
        uint64_t v3 = seed + 0;
        uint64_t v4 = seed - XXH_P1;

        do {
            v1 = xxh_round(v1, xxh_read64(p)); p += 8;
            v2 = xxh_round(v2, xxh_read64(p)); p += 8;
            v3 = xxh_round(v3, xxh_read64(p)); p += 8;
            v4 = xxh_round(v4, xxh_read64(p)); p += 8;
        } while (p <= limit);

        h64 = xxh_rotl64(v1, 1) + xxh_rotl64(v2, 7) +
              xxh_rotl64(v3, 12) + xxh_rotl64(v4, 18);
        h64 = xxh_mergeround(h64, v1);
        h64 = xxh_mergeround(h64, v2);
        h64 = xxh_mergeround(h64, v3);
        h64 = xxh_mergeround(h64, v4);
    } else {
        h64 = seed + XXH_P5;
    }

    h64 += (uint64_t)len;

    while (p + 8 <= end) {
        uint64_t k1 = xxh_round(0, xxh_read64(p));
        h64 ^= k1;
        h64 = xxh_rotl64(h64, 27) * XXH_P1 + XXH_P4;
        p += 8;
    }
    if (p + 4 <= end) {
        h64 ^= (uint64_t)xxh_read32(p) * XXH_P1;
        h64 = xxh_rotl64(h64, 23) * XXH_P2 + XXH_P3;
        p += 4;
    }
    while (p < end) {
        h64 ^= (uint64_t)(*p) * XXH_P5;
        h64 = xxh_rotl64(h64, 11) * XXH_P1;
        p++;
    }

    h64 ^= h64 >> 33;
    h64 *= XXH_P2;
    h64 ^= h64 >> 29;
    h64 *= XXH_P3;
    h64 ^= h64 >> 32;
    return h64;
}

/* ===================== SHA-256 (FIPS 180-4) ============================ */
static const uint32_t SHA256_K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

static inline uint32_t sha_rotr32(uint32_t x, int r) {
    return (x >> r) | (x << (32 - r));
}

/* One-shot: whole buffer is already in memory (mmap'd file or a small
 * directory-combine buffer), so we pad+process without a streaming
 * state machine. Uses a stack buffer for the common case (< 4KB after
 * padding) and falls back to heap only for large files. */
static void sha256_buf(const void *data, size_t len, uint8_t out[32]) {
    uint32_t h[8] = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
    };

    uint64_t bitlen = (uint64_t)len * 8ULL;
    size_t padded_len = ((len + 9 + 63) / 64) * 64;

    uint8_t stackbuf[4096];
    uint8_t *buf = stackbuf;
    bool heap = false;
    if (padded_len > sizeof(stackbuf)) {
        buf = (uint8_t *)malloc(padded_len);
        if (!buf) return;
        heap = true;
    }

    memcpy(buf, data, len);
    buf[len] = 0x80;
    memset(buf + len + 1, 0, padded_len - len - 1 - 8);
    for (int i = 0; i < 8; i++)
        buf[padded_len - 1 - i] = (uint8_t)(bitlen >> (8 * i));

    for (size_t chunk = 0; chunk < padded_len; chunk += 64) {
        uint32_t w[64];
        for (int i = 0; i < 16; i++) {
            const uint8_t *b = buf + chunk + i * 4;
            w[i] = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) |
                   ((uint32_t)b[2] << 8)  |  (uint32_t)b[3];
        }
        for (int i = 16; i < 64; i++) {
            uint32_t s0 = sha_rotr32(w[i-15], 7) ^ sha_rotr32(w[i-15], 18) ^ (w[i-15] >> 3);
            uint32_t s1 = sha_rotr32(w[i-2], 17) ^ sha_rotr32(w[i-2], 19) ^ (w[i-2] >> 10);
            w[i] = w[i-16] + s0 + w[i-7] + s1;
        }

        uint32_t a = h[0], b_ = h[1], c = h[2], d = h[3];
        uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];

        for (int i = 0; i < 64; i++) {
            uint32_t S1 = sha_rotr32(e, 6) ^ sha_rotr32(e, 11) ^ sha_rotr32(e, 25);
            uint32_t ch = (e & f) ^ (~e & g);
            uint32_t temp1 = hh + S1 + ch + SHA256_K[i] + w[i];
            uint32_t S0 = sha_rotr32(a, 2) ^ sha_rotr32(a, 13) ^ sha_rotr32(a, 22);
            uint32_t maj = (a & b_) ^ (a & c) ^ (b_ & c);
            uint32_t temp2 = S0 + maj;
            hh = g; g = f; f = e; e = d + temp1;
            d = c; c = b_; b_ = a; a = temp1 + temp2;
        }

        h[0]+=a; h[1]+=b_; h[2]+=c; h[3]+=d;
        h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;
    }

    for (int i = 0; i < 8; i++) {
        out[i*4]   = (uint8_t)(h[i] >> 24);
        out[i*4+1] = (uint8_t)(h[i] >> 16);
        out[i*4+2] = (uint8_t)(h[i] >> 8);
        out[i*4+3] = (uint8_t)(h[i]);
    }

    if (heap) free(buf);
}

/* ===================== public entry points ============================ */
void hash_compute(HashAlgo algo, const void *data, size_t len,
                   uint8_t out[HASH_MAX_BYTES], uint8_t *out_len) {
    memset(out, 0, HASH_MAX_BYTES);
    if (algo == HASH_ALGO_FAST) {
        uint64_t h = xxh64(data, len, 0);
        for (int i = 0; i < 8; i++) out[i] = (uint8_t)(h >> (56 - 8 * i));
        *out_len = 8;
    } else if (algo == HASH_ALGO_CRYPTO) {
        sha256_buf(data, len, out);
        *out_len = 32;
    } else {
        *out_len = 0;
    }
}

void hash_combine_children(HashAlgo algo,
                            char **names, uint8_t (*hashes)[HASH_MAX_BYTES],
                            uint8_t *hash_lens, size_t n,
                            uint8_t out[HASH_MAX_BYTES], uint8_t *out_len) {
    memset(out, 0, HASH_MAX_BYTES);
    if (algo == HASH_ALGO_NONE || n == 0) { *out_len = 0; return; }

    /* Build "<name>\0<hash bytes>" for each child, back to back, into
     * one scratch buffer, then hash that buffer once. Children are
     * already sorted by name, so this is order-stable. */
    size_t cap = 256, len = 0;
    uint8_t *scratch = (uint8_t *)malloc(cap);
    for (size_t i = 0; i < n; i++) {
        size_t namelen = strlen(names[i]) + 1; /* include NUL as separator */
        size_t need = len + namelen + hash_lens[i];
        if (need > cap) {
            while (cap < need) cap *= 2;
            scratch = (uint8_t *)realloc(scratch, cap);
        }
        memcpy(scratch + len, names[i], namelen);
        len += namelen;
        memcpy(scratch + len, hashes[i], hash_lens[i]);
        len += hash_lens[i];
    }

    hash_compute(algo, scratch, len, out, out_len);
    free(scratch);
}
