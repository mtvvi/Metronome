#ifndef REALTIME_PCM_BUFFER_H
#define REALTIME_PCM_BUFFER_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RealtimePCMBuffer RealtimePCMBuffer;

RealtimePCMBuffer *RealtimePCMBufferCreate(size_t capacity);
void RealtimePCMBufferDestroy(RealtimePCMBuffer *buffer);
size_t RealtimePCMBufferCapacity(const RealtimePCMBuffer *buffer);
size_t RealtimePCMBufferAvailableToRead(const RealtimePCMBuffer *buffer);
size_t RealtimePCMBufferWrite(
    RealtimePCMBuffer *buffer,
    const float *samples,
    size_t sampleCount
);
size_t RealtimePCMBufferRead(
    RealtimePCMBuffer *buffer,
    float *destination,
    size_t maximumSampleCount
);
void RealtimePCMBufferReset(RealtimePCMBuffer *buffer);

#ifdef __cplusplus
}
#endif

#endif
