/* English-only build: safe stand-ins for the Spanish backend.
 *
 * Upstream (RetroBunn/tv-decomp) added Spanish in 2026-09: src/port/api.c
 * carries one vtable row per language, so linking it requires the es_*
 * symbols even when Spanish is never used. Upstream links the real ones
 * from es/ + es_port/ with generated rename and data files (see its
 * harness/build.sh); iTruVoice ships English only, so this file provides
 * stand-ins that fail closed: es_create returns NULL, so asking for a
 * Spanish synth yields NULL rather than a half-built engine; setters are
 * no-ops; getters report 0/NULL. Nothing on the English path touches
 * them -- the corpus gate synthesizes English only, and deleting this
 * file makes the link fail on the es_* names, which is the tripwire that
 * it is still needed.
 *
 * Shipping Spanish voices later means linking the real backend per the
 * upstream recipe (gen_rename + tvdata_es), not extending this file.
 */
#include <stddef.h>
#include <stdint.h>

#include "tvtts_port.h"

void *es_create(uint32_t sample_rate) { (void)sample_rate; return NULL; }
void es_destroy(void *s) { (void)s; }
void es_set_voice(void *s, int voice) { (void)s; (void)voice; }
void es_set_rate(void *s, int wpm) { (void)s; (void)wpm; }
void es_set_pitch(void *s, int pitch) { (void)s; (void)pitch; }
void es_set_volume(void *s, uint32_t volume) { (void)s; (void)volume; }
int es_get_voice(const void *s) { (void)s; return 0; }
int es_get_rate(const void *s) { (void)s; return 0; }
int es_get_pitch(const void *s) { (void)s; return 0; }
uint32_t es_get_rate_hz(const void *s) { (void)s; return 0; }
int es_set_rate_hz(void *s, uint32_t hz) { (void)s; (void)hz; return -1; }
void es_set_compat(void *s, int preformat, int textin, int terminators) {
    (void)s; (void)preformat; (void)textin; (void)terminators;
}
void es_set_textin_mode(void *s, int mode) { (void)s; (void)mode; }
void es_set_extensions(uint32_t mask) { (void)mask; }
int es_voice_count(void) { return 0; }
const char *es_voice_name(int voice) { (void)voice; return NULL; }
int es_voice_rate(int voice) { (void)voice; return 0; }
int es_voice_pitch(int voice) { (void)voice; return 0; }
int es_speak_bytes(void *s, const void *text, uint32_t len,
                   tvtts_callback cb, void *user) {
    (void)s; (void)text; (void)len; (void)cb; (void)user;
    return -1;
}
