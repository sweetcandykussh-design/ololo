// fishhook — rebind symbols in Mach-O binaries at runtime.
// Copyright (c) 2013, Facebook, Inc. MIT License. Trimmed for in-tree use.

#ifndef fishhook_h
#define fishhook_h

#include <stddef.h>
#include <stdint.h>

#if !defined(FISHHOOK_EXPORT)
#define FISHHOOK_VISIBILITY __attribute__((visibility("hidden")))
#else
#define FISHHOOK_VISIBILITY
#endif

#ifdef __cplusplus
extern "C" {
#endif

/*
 * A structure representing a particular intended rebinding from a symbol
 * name to its replacement.
 */
struct rebinding {
  const char *name;
  void *replacement;
  void **replaced;
};

/*
 * Rebinds as many symbols as rebindings are passed, and rebinds the symbols
 * for all images loaded (and future ones via a dyld add-image callback).
 */
FISHHOOK_VISIBILITY
int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel);

/*
 * Rebinds as above but only for the specified image header/slide.
 */
FISHHOOK_VISIBILITY
int rebind_symbols_image(void *header,
                         intptr_t slide,
                         struct rebinding rebindings[],
                         size_t rebindings_nel);

#ifdef __cplusplus
}
#endif

#endif //fishhook_h
