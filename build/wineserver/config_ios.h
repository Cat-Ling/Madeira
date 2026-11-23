// Include the macOS-generated config.h first
#include "config.h"

// Override settings that differ on iOS
#undef HAVE_SYS_USER_H
#undef HAVE_SYS_PTRACE_H
#undef HAVE_NETINET_TCP_FSM_H
/* pipe2() is iOS 27+; undefining avoids a weak _pipe2 NULL jump on iOS <= 26. */
#undef HAVE_PIPE2

// Prevent mach.c from including mach_vm.h (unsupported on iOS)
// and servers/bootstrap.h (missing on iOS)
#ifdef __APPLE__
#define WINE_IOS 1
#endif
