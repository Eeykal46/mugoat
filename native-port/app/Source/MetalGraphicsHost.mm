// The app's graphics entry points (NativeGraphics.h), served by the native Metal renderer.
#include "NativeGraphics.h"
#include "MetalRenderer/MetalRenderer.h"
#include "NativeSmoothGovernor.h"
#import <Metal/Metal.h>
#include <stdlib.h>

extern "C" void pg_log(const char *);

void PGAttachMetalLayer(void *layer) { PGMetalRendererAttachLayer(layer); }
double PGRenderedFramesPerSecond(void) { return PGMetalRendererFPS(); }
void PGSetPresentPacing(double seconds) { PGMetalRendererSetPresentInterval(seconds); }
void PGCaptureNativeFrame(const char *name) { PGMetalRendererCapture(name); }

// Only the app's main thread configures and ticks the governor.
static PGSmoothGovernor smoothGovernor;
void PGSmoothConfigure(int32_t playerFrameLimit, double displayHz, int32_t minScalePermille) {
	smoothGovernor.configure(playerFrameLimit, displayHz, minScalePermille);
	double discard[3]; uint32_t frames;
	PGMetalRendererTakeSmoothSample(1e9, &frames, &discard[0], &discard[1], &discard[2]);	// start from an empty window
}
bool PGSmoothTick(int32_t thermalState, PGSmoothDecision *out) {
	PGSmoothSample sample;
	sample.thermal = thermalState;
	// late: an interval half a frame or more past the current target (a missed refresh at 60/120 Hz)
	PGMetalRendererTakeSmoothSample(smoothGovernor.targetMs() * 1.5, &sample.frames, &sample.p95Ms, &sample.lateFraction, &sample.gpuMsPerFrame);
	bool changed = smoothGovernor.step(sample);
	if (out) {
		out->scalePermille = smoothGovernor.scale; out->frameLimit = smoothGovernor.limit;
		out->presentInterval = smoothGovernor.presentInterval();
		out->p95Ms = sample.p95Ms; out->lateFraction = sample.lateFraction; out->gpuMsPerFrame = sample.gpuMsPerFrame; out->frames = sample.frames;
	}
	return changed;
}
void PGStartGraphics(void *memory, uint64_t memorySize, uint64_t ring, uint64_t ringSize, uint64_t) {
	if (!PGMetalRendererAvailable()) { pg_log("The Metal shader library is missing from the app: rebuild with the game's shaders."); return; }
	PGStartMetalRenderer(memory, memorySize, ring, ringSize);
}

int PGGPUReadsBC(void) {
	static int answer = -1;
	if (answer < 0) { id<MTLDevice> device = MTLCreateSystemDefaultDevice(); answer = 0; if (@available(iOS 16.4, *)) answer = device && device.supportsBCTextureCompression && !getenv("PG_FORCE_BC_DECODE"); }
	return answer;
}
