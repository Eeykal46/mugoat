#pragma once
#include <stdint.h>

// Limits of the pinned memory64 import (env.memory): 49152..262144 x 64 KiB.
// These are engine ABI constraints, not an app-imposed RAM allowance.
#define PG_ENGINE_MEMORY_MIN_BYTES (3072ull * 1048576)
#define PG_ENGINE_MEMORY_MAX_BYTES (16384ull * 1048576)

typedef struct {
 uint64_t initialPages;
 uint64_t maximumPages;
} PGEngineMemory;

// Pages for a reservation of physicalBytes (clamped to the ABI limits). Pages are
// committed on demand; the initial logical heap does not pre-touch the mapping.
// EngineHost.c decides the size: the app's memory limit plus slack, within the
// free address space (iOS 27 without extended-virtual-addressing has ~7 GiB).
static inline PGEngineMemory pg_engine_memory(uint64_t physicalBytes,uint64_t pageSize){
 PGEngineMemory result={0,0};
 if(!pageSize)return result;
 uint64_t minimum=(PG_ENGINE_MEMORY_MIN_BYTES+pageSize-1)/pageSize;
 uint64_t engineMaximum=PG_ENGINE_MEMORY_MAX_BYTES/pageSize;
 uint64_t capacity=(physicalBytes?physicalBytes:PG_ENGINE_MEMORY_MAX_BYTES)/pageSize;
 if(capacity>engineMaximum)capacity=engineMaximum;
 if(capacity<minimum)capacity=minimum;
 uint64_t initial=(3328ull*1048576+pageSize-1)/pageSize;
 result.initialPages=initial<capacity?initial:capacity;
 result.maximumPages=capacity;
 return result;
}
