/* Playport (PLA-846, decision 0184): the JIT pool's room, the pages nothing
 * has used yet between the head and the tail. Blessing writes a byte to every
 * page of the pool, so each page is dirty from activation on and the whole pool
 * counted against the memory limit. At the pool's start the room is made
 * reusable (MADV_FREE_REUSABLE through the RW alias): out of the footprint,
 * though iOS may take a page back. A page is claimed once, just before the head
 * or the tail first hands it out: virtual_ios.c (ios_pool_room_take) cancels
 * reusable, reads the page through the RX mapping, the blessed one, so a page
 * iOS took back comes back through it, and writes it through the RW alias, so
 * it is dirty and iOS never drops it again. This header keeps which pages are
 * claimed. */
#ifndef PP_JIT_ROOM_H
#define PP_JIT_ROOM_H

#include <stddef.h>

#define PPJR_PAGE ((size_t)0x4000)

struct ppjr
{
    unsigned char *claimed;   /* a bit per pool page, set once claimed; NULL: no room */
    size_t pages;             /* pool pages */
    size_t first;             /* the room's first page: those below were never reusable */
    unsigned long claims;     /* room pages claimed (including pre-marked split-pool holes) */
    unsigned long taken;      /* of those, pages iOS had taken back while they were room */
};

/* Makes the pool's [off, off + len) usable; returns how many of its pages iOS had taken back. */
typedef unsigned long (*ppjr_take_fn)( void *ctx, size_t off, size_t len );

/* bits: (pool_size / PPJR_PAGE + 7) / 8 zeroed bytes. The room is [first_off, pool_size).
 * 0 when set up; -1 and no room for a size or start off the page grid or no room at all. */
static inline int ppjr_init( struct ppjr *r, unsigned char *bits, size_t pool_size, size_t first_off )
{
    r->claimed = NULL;
    r->pages = r->first = 0;
    r->claims = r->taken = 0;
    if (!bits || pool_size % PPJR_PAGE || first_off % PPJR_PAGE || first_off >= pool_size) return -1;
    r->claimed = bits;
    r->pages = pool_size / PPJR_PAGE;
    r->first = first_off / PPJR_PAGE;
    return 0;
}

static inline int ppjr_is_claimed( const struct ppjr *r, size_t page )
{
    return (r->claimed[page / 8] & (1u << (page % 8))) != 0;
}

static inline size_t ppjr_end_page( const struct ppjr *r, size_t off, size_t size )
{
    size_t end;
    if (size > (size_t)-1 - off || off + size > (size_t)-1 - (PPJR_PAGE - 1)) return r->pages;
    end = (off + size + PPJR_PAGE - 1) / PPJR_PAGE;
    return end > r->pages ? r->pages : end;
}

/* Marks [off, off + size) as already excluded from the reusable room (used for
 * split-pool PROT_NONE holes that must never be touched). */
static inline size_t ppjr_mark_claimed( struct ppjr *r, size_t off, size_t size )
{
    size_t p, end, marked = 0;

    if (!r->claimed || !size) return 0;
    p = off / PPJR_PAGE;
    end = ppjr_end_page( r, off, size );
    if (p < r->first) p = r->first;
    while (p < end)
    {
        if (!ppjr_is_claimed( r, p ))
        {
            r->claimed[p / 8] |= (unsigned char)(1u << (p % 8));
            r->claims++;
            marked++;
        }
        p++;
    }
    return marked;
}

/* Claims the room's unclaimed pages in [off, off + size), a run of them at a time, calling take
 * for each run before marking it; returns the pages claimed now. */
static inline size_t ppjr_claim( struct ppjr *r, size_t off, size_t size, ppjr_take_fn take, void *ctx )
{
    size_t p, end, done = 0;

    if (!r->claimed || !size) return 0;
    p = off / PPJR_PAGE;
    end = ppjr_end_page( r, off, size );
    if (p < r->first) p = r->first;
    while (p < end)
    {
        size_t q;
        if (ppjr_is_claimed( r, p )) { p++; continue; }
        for (q = p; q < end && !ppjr_is_claimed( r, q ); q++) {}
        r->taken += take( ctx, p * PPJR_PAGE, (q - p) * PPJR_PAGE );
        r->claims += q - p;
        done += q - p;
        for (; p < q; p++) r->claimed[p / 8] |= (unsigned char)(1u << (p % 8));
    }
    return done;
}

/* The room still out of the footprint, in bytes: the room's pages not yet claimed. */
static inline size_t ppjr_room_bytes( const struct ppjr *r )
{
    if (!r->claimed) return 0;
    return (r->pages - r->first - r->claims) * PPJR_PAGE;
}

#endif /* PP_JIT_ROOM_H */
