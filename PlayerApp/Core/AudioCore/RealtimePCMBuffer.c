#include "RealtimePCMBuffer.h"

#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>

struct RealtimePCMBuffer {
    float *storage;
    size_t capacity;
    _Atomic size_t readIndex;
    _Atomic size_t writeIndex;
};

RealtimePCMBuffer *RealtimePCMBufferCreate(size_t capacity) {
    if (capacity == 0 || capacity > SIZE_MAX / sizeof(float)) {
        return NULL;
    }
    RealtimePCMBuffer *buffer = calloc(1, sizeof(RealtimePCMBuffer));
    if (buffer == NULL) {
        return NULL;
    }
    buffer->storage = calloc(capacity, sizeof(float));
    if (buffer->storage == NULL) {
        free(buffer);
        return NULL;
    }
    buffer->capacity = capacity;
    atomic_init(&buffer->readIndex, 0);
    atomic_init(&buffer->writeIndex, 0);
    return buffer;
}

void RealtimePCMBufferDestroy(RealtimePCMBuffer *buffer) {
    if (buffer == NULL) {
        return;
    }
    free(buffer->storage);
    buffer->storage = NULL;
    buffer->capacity = 0;
    free(buffer);
}

size_t RealtimePCMBufferCapacity(const RealtimePCMBuffer *buffer) {
    return buffer == NULL ? 0 : buffer->capacity;
}

size_t RealtimePCMBufferAvailableToRead(const RealtimePCMBuffer *buffer) {
    if (buffer == NULL) {
        return 0;
    }
    const size_t readIndex = atomic_load_explicit(&buffer->readIndex, memory_order_acquire);
    const size_t writeIndex = atomic_load_explicit(&buffer->writeIndex, memory_order_acquire);
    return writeIndex - readIndex;
}

size_t RealtimePCMBufferWrite(
    RealtimePCMBuffer *buffer,
    const float *samples,
    size_t sampleCount
) {
    if (buffer == NULL || samples == NULL || sampleCount == 0) {
        return 0;
    }
    const size_t writeIndex = atomic_load_explicit(&buffer->writeIndex, memory_order_relaxed);
    const size_t readIndex = atomic_load_explicit(&buffer->readIndex, memory_order_acquire);
    const size_t used = writeIndex - readIndex;
    const size_t freeCount = used < buffer->capacity ? buffer->capacity - used : 0;
    const size_t accepted = sampleCount < freeCount ? sampleCount : freeCount;
    for (size_t index = 0; index < accepted; ++index) {
        buffer->storage[(writeIndex + index) % buffer->capacity] = samples[index];
    }
    atomic_store_explicit(&buffer->writeIndex, writeIndex + accepted, memory_order_release);
    return accepted;
}

size_t RealtimePCMBufferRead(
    RealtimePCMBuffer *buffer,
    float *destination,
    size_t maximumSampleCount
) {
    if (buffer == NULL || destination == NULL || maximumSampleCount == 0) {
        return 0;
    }
    const size_t readIndex = atomic_load_explicit(&buffer->readIndex, memory_order_relaxed);
    const size_t writeIndex = atomic_load_explicit(&buffer->writeIndex, memory_order_acquire);
    const size_t available = writeIndex - readIndex;
    const size_t readCount = maximumSampleCount < available ? maximumSampleCount : available;
    for (size_t index = 0; index < readCount; ++index) {
        destination[index] = buffer->storage[(readIndex + index) % buffer->capacity];
    }
    atomic_store_explicit(&buffer->readIndex, readIndex + readCount, memory_order_release);
    return readCount;
}

void RealtimePCMBufferReset(RealtimePCMBuffer *buffer) {
    if (buffer == NULL) {
        return;
    }
    const size_t writeIndex = atomic_load_explicit(&buffer->writeIndex, memory_order_acquire);
    atomic_store_explicit(&buffer->readIndex, writeIndex, memory_order_release);
}
