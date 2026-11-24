#pragma once
#include <stdint.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
// Native Metal renderer (Source/MetalRenderer): executes the game's graphics command ring directly on Metal.
bool PGMetalRendererAvailable(void);
void PGMetalRendererAttachLayer(void *layer);
void PGStartMetalRenderer(void *memory, uint64_t memorySize, uint64_t ring, uint64_t ringSize);
double PGMetalRendererFPS(void);
// Minimum time each frame stays on screen (1/cap), 0 to present as soon as possible.
void PGMetalRendererSetPresentInterval(double seconds);
void PGMetalRendererCapture(const char *name);
// Auto-smooth: the present intervals and GPU time since the last call (world frames only), then resets.
// lateFraction counts intervals of lateMs or longer. False when no frame was recorded.
// Performance log window (world frames since the last call), then resets. Over-N counts frames longer than N ms.
bool PGMetalRendererTakePerfWindow(uint64_t *frames, uint64_t *over33, uint64_t *over50, uint64_t *over100,
	double *fps, double *p95Ms, double *p99Ms, double *maxMs, double *gpuMsPerFrame);
bool PGMetalRendererTakeSmoothSample(double lateMs, uint32_t *frames, double *p95Ms, double *lateFraction, double *gpuMsPerFrame);
#ifdef __cplusplus
}
#endif
