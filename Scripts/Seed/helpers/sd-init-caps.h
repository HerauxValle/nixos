#ifndef SD_INIT_CAPS_H
#define SD_INIT_CAPS_H

#include <linux/capability.h>
#include <sys/prctl.h>
#include <stdio.h>
#include <string.h>

static int drop_caps_except(const char **keep_caps, int keep_count) {
    unsigned int cap;
    int found;

    /* Get current capability bounding set size */
    unsigned int cap_max = CAP_LAST_CAP;

    /* Drop all capabilities except those in keep list */
    for (cap = 0; cap <= cap_max; cap++) {
        found = 0;
        for (int i = 0; i < keep_count; i++) {
            if (cap == CAP_NET_BIND_SERVICE && strcmp(keep_caps[i], "NET_BIND_SERVICE") == 0) found = 1;
            if (cap == CAP_CHOWN && strcmp(keep_caps[i], "CHOWN") == 0) found = 1;
            if (cap == CAP_DAC_OVERRIDE && strcmp(keep_caps[i], "DAC_OVERRIDE") == 0) found = 1;
            if (cap == CAP_SETFCAP && strcmp(keep_caps[i], "SETFCAP") == 0) found = 1;
        }
        if (!found) {
            if (prctl(PR_CAPBSET_DROP, cap, 0, 0, 0) < 0 && cap != cap_max) {
                /* Ignore errors for non-existent caps in some kernels */
            }
        }
    }

    /* Clear effective, permitted, inheritable sets; keep only explicit caps */
    cap_user_header_t hdr = malloc(sizeof(struct __user_cap_header_struct));
    cap_user_data_t data = malloc(sizeof(struct __user_cap_data_struct) * 2);

    if (!hdr || !data) return -1;

    hdr->version = _LINUX_CAPABILITY_VERSION_3;
    hdr->pid = 0;

    memset(data, 0, sizeof(struct __user_cap_data_struct) * 2);

    /* Only keep explicitly allowed caps in effective set */
    for (int i = 0; i < keep_count; i++) {
        if (strcmp(keep_caps[i], "NET_BIND_SERVICE") == 0) {
            data[0].effective |= (1 << CAP_NET_BIND_SERVICE);
            data[0].permitted |= (1 << CAP_NET_BIND_SERVICE);
        }
        if (strcmp(keep_caps[i], "CHOWN") == 0) {
            data[0].effective |= (1 << CAP_CHOWN);
            data[0].permitted |= (1 << CAP_CHOWN);
        }
        if (strcmp(keep_caps[i], "DAC_OVERRIDE") == 0) {
            data[0].effective |= (1 << CAP_DAC_OVERRIDE);
            data[0].permitted |= (1 << CAP_DAC_OVERRIDE);
        }
        if (strcmp(keep_caps[i], "SETFCAP") == 0) {
            data[0].effective |= (1 << CAP_SETFCAP);
            data[0].permitted |= (1 << CAP_SETFCAP);
        }
    }

    int ret = capset(hdr, data);
    free(hdr);
    free(data);
    return ret;
}

#endif
