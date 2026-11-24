#pragma once
#include <stdint.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
void PGCaptureNativeFrame(const char *name);
double PGRenderedFramesPerSecond(void);
void PGSetPresentPacing(double seconds);
void PGAttachMetalLayer(void *layer);
void PGStartGraphics(void *memory,uint64_t memorySize,uint64_t ring,uint64_t ringSize,uint64_t debug);
// The GPU samples BC textures as they are (otherwise they are decoded, about 4 times larger).
int PGGPUReadsBC(void);

// Auto-smooth (NativeSmoothGovernor.h). Configure when the engine starts with the player's frame-limit
// code (0 off, 1 = 60, 2 = 30), the screen's maximum rate and the lowest resolution share in permille.
typedef struct {
	int32_t scalePermille;		// share of the chosen render height to use now
	int32_t frameLimit;			// engine frame-limit code for PGSetFrameLimit
	double presentInterval;		// seconds for PGSetPresentPacing (0: present as soon as possible)
	double p95Ms, lateFraction, gpuMsPerFrame;	// the window behind this decision, for the log/HUD
	uint32_t frames;
} PGSmoothDecision;
void PGSmoothConfigure(int32_t playerFrameLimit, double displayHz, int32_t minScalePermille);
// Takes one window from the renderer and steps the governor. True when scale or frame limit changed.
bool PGSmoothTick(int32_t thermalState, PGSmoothDecision *out);

// One performance-log window of world frames (the app takes one a minute). False when no frame was recorded.
typedef struct {
	uint64_t frames, over33, over50, over100;	// frames longer than 33/50/100 ms
	double fps, p95Ms, p99Ms, maxMs, gpuMsPerFrame;
} PGPerfWindow;
bool PGTakePerfWindow(PGPerfWindow *out);
// Renderer counters since launch (the performance log takes differences) and memory now, in bytes.
typedef struct {
	uint64_t skippedDraws, pipelineWaitSkips, pipelinesMade, textureCreateFailures, backgroundHolds;
	uint64_t textureBytes, bcTextureBytes, metalAllocatedBytes;
} PGRenderCounters;
bool PGReadRenderCounters(PGRenderCounters *out);
// The app is in the background: the renderer holds GPU work (iOS refuses it) until it returns.
void PGSetAppInBackground(bool background);
// Frames the renderer has presented since launch (stops while the app is in the background).
uint64_t PGPresentedFrames(void);
// Performance overlay: up to `max` of the latest world frame intervals (ms, oldest first) and the
// smoothed GPU time per frame. Returns how many were written.
int PGHUDFrameTimes(float *out, int max, double *gpuMs);
#ifdef __cplusplus
}
#endif
