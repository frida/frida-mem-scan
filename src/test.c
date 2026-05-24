#include <dispatch/dispatch.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MASK 0x00007ffffffffff8ULL

typedef void (* dispatch_apply_f_t) (size_t, dispatch_queue_t, void *,
    void (*) (void *, size_t));

extern uint64_t scan (const uint64_t * buf, uint64_t qcount,
    uint64_t mask,
    const uint64_t * targets, uint64_t ntargets,
    uint32_t * out, uint64_t out_cap);
extern uint64_t scan1 (const uint64_t * buf, uint64_t qcount,
    uint64_t mask, uint64_t target,
    uint32_t * out, uint64_t out_cap);
extern void scan_parallel (dispatch_apply_f_t f, dispatch_queue_t q,
    const uint64_t * buf, uint64_t qcount,
    uint64_t mask,
    const uint64_t * targets, uint64_t ntargets,
    uint32_t * out, uint64_t out_cap,
    uint64_t * out_counts, uint64_t * out_offs,
    uint64_t nthreads);
extern void scan1_parallel (dispatch_apply_f_t f, dispatch_queue_t q,
    const uint64_t * buf, uint64_t qcount,
    uint64_t mask, uint64_t target,
    uint32_t * out, uint64_t out_cap,
    uint64_t * out_counts, uint64_t * out_offs,
    uint64_t nthreads);

static void test_basic (void);
static void test_capacity (void);
static void test_odd_length (void);
static void test_many_targets (void);
static void test_scan1 (void);
static void perf (void);
static void perf_parallel (void);
static void perf_scan1 (void);
static void check (const char * what, uint64_t got, uint64_t want);

static int fail = 0;

int
main (void)
{
  test_basic ();
  test_capacity ();
  test_odd_length ();
  test_many_targets ();
  test_scan1 ();
  perf ();
  perf_parallel ();
  perf_scan1 ();
  return fail;
}

static void
test_basic (void)
{
  uint64_t buf[16];
  uint64_t targets[2] = { 0x123450ULL, 0xabcde0ULL };
  uint32_t out[8];
  uint64_t hits;

  printf ("test_basic\n");
  for (int i = 0; i < 16; i++)
    buf[i] = 0xdead0000UL + i;
  buf[5]  = targets[0] | 0xff00000000000007ULL;
  buf[11] = targets[1] | 0x0700000000000005ULL;

  hits = scan (buf, 16, MASK, targets, 2, out, 8);
  check ("hits", hits, 2);
  check ("out[0]", out[0], 5);
  check ("out[1]", out[1], 11);
}

static void
test_capacity (void)
{
  uint64_t buf[8];
  uint64_t target = 0x111100ULL;
  uint32_t out[3];
  uint64_t hits;

  printf ("test_capacity\n");
  for (int i = 0; i < 8; i++)
    buf[i] = target;
  hits = scan (buf, 8, MASK, &target, 1, out, 3);
  check ("hits (returns total even when truncated)", hits, 8);
  check ("out[0]", out[0], 0);
  check ("out[1]", out[1], 1);
  check ("out[2]", out[2], 2);
}

static void
test_odd_length (void)
{
  uint64_t buf[5] = { 0, 0, 0x40, 0, 0x40 };
  uint64_t target = 0x40;
  uint32_t out[4];
  uint64_t hits;

  printf ("test_odd_length\n");
  hits = scan (buf, 5, MASK, &target, 1, out, 4);
  check ("hits", hits, 2);
  check ("out[0]", out[0], 2);
  check ("out[1]", out[1], 4);
}

static void
test_many_targets (void)
{
  uint64_t buf[10];
  uint64_t targets[6] = {
    0x100, 0x140, 0x180, 0xdeadbeef, 0xcafef00d, 0x190
  };
  uint32_t out[10];
  uint64_t hits;

  printf ("test_many_targets (scalar path)\n");
  for (int i = 0; i < 10; i++)
    buf[i] = 0x100 + i * 0x10;
  hits = scan (buf, 10, MASK, targets, 6, out, 10);
  check ("hits", hits, 4);
  check ("out[0]", out[0], 0);
  check ("out[1]", out[1], 4);
  check ("out[2]", out[2], 8);
  check ("out[3]", out[3], 9);
}

static void
test_scan1 (void)
{
  uint64_t buf[20];
  uint32_t out[8];
  uint64_t hits;

  printf ("test_scan1\n");
  for (int i = 0; i < 20; i++)
    buf[i] = 0xdead0000ULL + i;
  buf[2]  = 0x111100ULL | 0xff00000000000007ULL;
  buf[7]  = 0x111100ULL;
  buf[14] = 0x111100ULL | 0x0700000000000005ULL;
  buf[19] = 0x111100ULL;

  hits = scan1 (buf, 20, MASK, 0x111100ULL, out, 8);
  check ("hits", hits, 4);
  check ("out[0]", out[0], 2);
  check ("out[1]", out[1], 7);
  check ("out[2]", out[2], 14);
  check ("out[3]", out[3], 19);
}

static void
perf (void)
{
  size_t n = 64 * 1024 * 1024;
  uint64_t * buf = aligned_alloc (64, n * sizeof (uint64_t));
  uint64_t targets[4] = { 0xdeadbeef00ULL, 0xcafef00d00ULL,
                          0xbadc0ffee0ULL, 0x100ULL };
  uint32_t * out = malloc (1024 * sizeof (uint32_t));
  struct timespec t0, t1;
  uint64_t hits;
  double seconds, mb_per_s;

  printf ("perf\n");
  for (size_t i = 0; i < n; i++)
    buf[i] = (uint64_t) i;

  clock_gettime (CLOCK_MONOTONIC, &t0);
  hits = scan (buf, n, MASK, targets, 4, out, 1024);
  clock_gettime (CLOCK_MONOTONIC, &t1);
  seconds = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
  mb_per_s = (n * sizeof (uint64_t)) / seconds / (1024.0 * 1024.0);
  printf ("  scanned %zu MB in %.3fs (%.1f MB/s), hits=%llu\n",
      (n * sizeof (uint64_t)) >> 20, seconds, mb_per_s, hits);

  free (out);
  free (buf);
}

static void
perf_parallel (void)
{
  size_t n = 64 * 1024 * 1024;
  uint64_t * buf = aligned_alloc (64, n * sizeof (uint64_t));
  uint64_t targets[4] = { 0xdeadbeef00ULL, 0xcafef00d00ULL,
                          0xbadc0ffee0ULL, 0x100ULL };
  uint64_t T = 8, cap = 256;
  uint32_t * out_flat = malloc (T * cap * sizeof (uint32_t));
  uint64_t * counts = calloc (T, sizeof (uint64_t));
  uint64_t * offs = calloc (T, sizeof (uint64_t));
  dispatch_queue_t q;
  struct timespec t0, t1;
  uint64_t total = 0;
  double seconds, mb_per_s;

  printf ("perf_parallel\n");
  for (size_t i = 0; i < n; i++)
    buf[i] = (uint64_t) i;
  q = dispatch_get_global_queue (QOS_CLASS_USER_INITIATED, 0);

  clock_gettime (CLOCK_MONOTONIC, &t0);
  scan_parallel (dispatch_apply_f, q,
      buf, n, MASK, targets, 4,
      out_flat, cap, counts, offs, T);
  clock_gettime (CLOCK_MONOTONIC, &t1);
  seconds = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
  mb_per_s = (n * sizeof (uint64_t)) / seconds / (1024.0 * 1024.0);
  for (uint64_t i = 0; i < T; i++)
    total += counts[i];
  printf ("  %llu threads: scanned %zu MB in %.3fs (%.1f MB/s), "
      "hits=%llu\n", T, (n * sizeof (uint64_t)) >> 20, seconds,
      mb_per_s, total);

  free (offs);
  free (counts);
  free (out_flat);
  free (buf);
}

static void
perf_scan1 (void)
{
  size_t n = 64 * 1024 * 1024;
  uint64_t * buf = aligned_alloc (64, n * sizeof (uint64_t));
  uint32_t * out = malloc (1024 * sizeof (uint32_t));
  uint64_t T = 8, cap = 256;
  uint32_t * out_flat = malloc (T * cap * sizeof (uint32_t));
  uint64_t * counts = calloc (T, sizeof (uint64_t));
  uint64_t * offs = calloc (T, sizeof (uint64_t));
  dispatch_queue_t q;
  struct timespec t0, t1;
  uint64_t hits, total = 0;
  double seconds, mb_per_s;

  printf ("perf_scan1\n");
  for (size_t i = 0; i < n; i++)
    buf[i] = (uint64_t) i;

  clock_gettime (CLOCK_MONOTONIC, &t0);
  hits = scan1 (buf, n, MASK, 0x100ULL, out, 1024);
  clock_gettime (CLOCK_MONOTONIC, &t1);
  seconds = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
  mb_per_s = (n * sizeof (uint64_t)) / seconds / (1024.0 * 1024.0);
  printf ("  single-target: %zu MB in %.3fs (%.1f MB/s), hits=%llu\n",
      (n * sizeof (uint64_t)) >> 20, seconds, mb_per_s, hits);

  q = dispatch_get_global_queue (QOS_CLASS_USER_INITIATED, 0);
  clock_gettime (CLOCK_MONOTONIC, &t0);
  scan1_parallel (dispatch_apply_f, q, buf, n, MASK, 0x100ULL,
      out_flat, cap, counts, offs, T);
  clock_gettime (CLOCK_MONOTONIC, &t1);
  seconds = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
  mb_per_s = (n * sizeof (uint64_t)) / seconds / (1024.0 * 1024.0);
  for (uint64_t i = 0; i < T; i++)
    total += counts[i];
  printf ("  parallel %llu thr: %zu MB in %.3fs (%.1f MB/s), hits=%llu\n",
      T, (n * sizeof (uint64_t)) >> 20, seconds, mb_per_s, total);

  free (offs);
  free (counts);
  free (out_flat);
  free (out);
  free (buf);
}

static void
check (const char * what, uint64_t got, uint64_t want)
{
  if (got == want)
  {
    printf ("  ok   %s = %llu\n", what, got);
  }
  else
  {
    printf ("  FAIL %s: got %llu, want %llu\n", what, got, want);
    fail = 1;
  }
}
