// Links against libgmbridge.a and exercises the ABI without the network:
// session lifecycle, an unknown method, and freeing returned buffers.
#include <stdio.h>
#include <string.h>
#include "../build/libgmbridge.h"

static int events = 0;
static void on_event(void *ctx, int32_t kind, const uint8_t *data, int64_t len) { events++; }

int main(void) {
    int64_t h = gm_session_new(NULL, 0, on_event, NULL);
    if (h <= 0) { puts("FAIL session_new"); return 1; }
    uint8_t *out = NULL; int64_t n = 0;
    int32_t rc = gm_call(h, 999, NULL, 0, &out, &n);
    if (rc != -1 || !out) { puts("FAIL expected error"); return 1; }
    printf("unknown method -> rc=%d err=%.*s\n", rc, (int)n, out);
    gm_free(out);
    const char *bad = "{not json";
    int64_t h2 = gm_session_new((uint8_t*)bad, strlen(bad), on_event, NULL);
    printf("bad auth json -> handle=%lld (want 0)\n", (long long)h2);
    rc = gm_call(12345, 1, NULL, 0, &out, &n);
    printf("bad handle -> rc=%d err=%.*s\n", rc, (int)n, out); gm_free(out);
    gm_session_free(h);
    gm_session_free(h); // double free of a handle is a no-op
    puts(h2 == 0 ? "PASS" : "FAIL");
    return h2 == 0 ? 0 : 1;
}
