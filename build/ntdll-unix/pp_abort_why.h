/* Playport (PLA-880): why host code called abort() on a thread of a game.
 *
 * SIGABRT from host code on a thread with a TEB becomes the game's
 * EXCEPTION_WINE_ASSERTION (0x80000101, abrt_handler), and the game ends with
 * that code and nothing else: The Witcher 3's dxvk-cs thread did, inside
 * winevulkan, at a pc in libsystem_kernel. The library that aborts leaves its
 * reason in its crash-reporter annotations (the __crash_info section an iOS
 * crash report reads as "Application Specific Information": Metal's failed
 * assertion, libc's assert, an uncaught Objective-C or C++ exception, a
 * malloc error), and the host frames above the abort name the caller. These
 * are the parts of finding them that need no Apple headers: a Mach-O image's
 * section by name, the messages of an annotation, and a walk of a frame
 * pointer chain through a reader that may refuse an address. The handler
 * (signal_arm64_ios.c) reads with mach_vm_read_overwrite, so a bad pointer
 * ends a walk instead of faulting in the handler. */
#ifndef PP_ABORT_WHY_H
#define PP_ABORT_WHY_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define PPAW_MH_MAGIC_64 0xfeedfacfu
#define PPAW_LC_SEGMENT_64 0x19u

struct ppaw_mach_header {
    uint32_t magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved;
};
struct ppaw_load_command {
    uint32_t cmd, cmdsize;
};
struct ppaw_segment {
    uint32_t cmd, cmdsize;
    char segname[16];
    uint64_t vmaddr, vmsize, fileoff, filesize;
    uint32_t maxprot, initprot, nsects, flags;
};
struct ppaw_section {
    char sectname[16], segname[16];
    uint64_t addr, size;
    uint32_t offset, align, reloff, nreloc, flags, reserved1, reserved2, reserved3;
};

/* The loaded (slid) address and size of the 64-bit image's first section of
 * that name, in any segment: __crash_info is in __DATA, or in __DATA_DIRTY in
 * the shared cache. 0 when the header is not one or has no such section. */
static inline int ppaw_find_section( const void *header, intptr_t slide, const char *name,
                                     uint64_t *addr, uint64_t *size )
{
    const struct ppaw_mach_header *mh = header;
    const uint8_t *p, *end;
    uint32_t i, j;

    if (!mh || mh->magic != PPAW_MH_MAGIC_64) return 0;
    p = (const uint8_t *)(mh + 1);
    end = p + mh->sizeofcmds;
    for (i = 0; i < mh->ncmds; i++)
    {
        const struct ppaw_load_command *lc = (const void *)p;
        if ((size_t)(end - p) < sizeof(*lc) || lc->cmdsize < sizeof(*lc) ||
            lc->cmdsize > (size_t)(end - p))
            return 0;
        if (lc->cmd == PPAW_LC_SEGMENT_64)
        {
            const struct ppaw_segment *seg = (const void *)p;
            const struct ppaw_section *sect = (const void *)(seg + 1);
            if (lc->cmdsize < sizeof(*seg) ||
                (uint64_t)seg->nsects * sizeof(*sect) > lc->cmdsize - sizeof(*seg))
                return 0;
            for (j = 0; j < seg->nsects; j++)
            {
                if (strncmp( sect[j].sectname, name, sizeof(sect[j].sectname) )) continue;
                *addr = sect[j].addr + (uint64_t)slide;
                *size = sect[j].size;
                return 1;
            }
        }
        p += lc->cmdsize;
    }
    return 0;
}

/* CrashReporterClient's crashreporter_annotations_t (version 5) */
struct ppaw_crash_info {
    uint64_t version;          /* 0: never filled */
    uint64_t message;          /* char *, CRSetCrashLogMessage */
    uint64_t signature_string;
    uint64_t backtrace;
    uint64_t message2;         /* char *, CRSetCrashLogMessage2 */
    uint64_t thread;
    uint64_t dialog_mode;
    uint64_t abort_cause;      /* version 5 */
};

/* The message pointers of an annotation the section held `size` bytes of,
 * into msgs (message, then message2), and its abort cause (0 if none): how
 * many messages */
static inline unsigned ppaw_crash_messages( const struct ppaw_crash_info *info, uint64_t size,
                                            uint64_t msgs[2], uint64_t *abort_cause )
{
    unsigned n = 0;

    *abort_cause = 0;
    if (size < offsetof(struct ppaw_crash_info, message) + sizeof(uint64_t) || !info->version)
        return 0;
    if (info->message) msgs[n++] = info->message;
    if (size >= offsetof(struct ppaw_crash_info, message2) + sizeof(uint64_t) && info->message2)
        msgs[n++] = info->message2;
    if (info->version >= 5 && size >= sizeof(*info)) *abort_cause = info->abort_cause;
    return n;
}

/* A frame pointer chain's return addresses, from fp: each frame is the
 * caller's fp and the return address. It ends at a frame the reader refuses,
 * an fp that is not 8-aligned, does not grow toward older frames or jumps more
 * than PPAW_FRAME_MAX, or a return address of 0. */
#define PPAW_FRAME_MAX (8u << 20)
typedef int (*ppaw_reader)( uint64_t addr, uint64_t frame[2], void *ctx );

static inline unsigned ppaw_walk( uint64_t fp, ppaw_reader read, void *ctx, uint64_t *ret,
                                  unsigned max )
{
    unsigned n = 0;

    while (n < max && fp && !(fp & 7))
    {
        uint64_t frame[2];
        if (!read( fp, frame, ctx ) || !frame[1]) break;
        ret[n++] = frame[1];
        if (frame[0] <= fp || frame[0] - fp > PPAW_FRAME_MAX) break;
        fp = frame[0];
    }
    return n;
}

#endif /* PP_ABORT_WHY_H */
