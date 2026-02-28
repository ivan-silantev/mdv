#ifndef MDV_RENDERER_H
#define MDV_RENDERER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    MDV_RENDER_OK = 0,
    MDV_RENDER_INVALID_ARGUMENT = 1,
    MDV_RENDER_FAILED = 2,
};

int mdv_render_html(
    const uint8_t *markdown_ptr,
    size_t markdown_len,
    uint8_t **out_ptr,
    size_t *out_len);

int mdv_render_terminal(
    const uint8_t *markdown_ptr,
    size_t markdown_len,
    uint32_t cols,
    uint32_t rows,
    bool use_color,
    uint8_t **out_ptr,
    size_t *out_len);

void mdv_free_rendered(uint8_t *ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif
