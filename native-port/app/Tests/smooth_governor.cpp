#include "NativeSmoothGovernor.h"
#include <cassert>
#include <cstdio>

static PGSmoothSample window(double intervalMs, double lateEvery, double lateMs, double gpuMs, int thermal = 0, int frames = 60) {
	PGPresentIntervalWindow w;
	for (int i = 0; i < frames; i++) {
		bool late = lateEvery > 0 && i % (int)lateEvery == 0;
		w.record(late ? lateMs : intervalMs);
		w.addGPU(gpuMs);
	}
	PGSmoothSample s;
	s.frames = w.frames; s.p95Ms = w.percentile(.95); s.gpuMsPerFrame = w.gpuMsPerFrame(); s.thermal = thermal;
	return s;
}
static PGSmoothSample withLate(PGSmoothSample s, const PGPresentIntervalWindow &w, double target) { s.lateFraction = w.fractionAtLeast(target * 1.5); return s; }

int main() {
	// window statistics
	PGPresentIntervalWindow w;
	assert(!w.record(NAN) && !w.record(0) && !w.record(-1) && !w.record(5000));
	for (int i = 0; i < 95; i++) w.record(16.6);
	for (int i = 0; i < 5; i++) w.record(50);
	assert(w.frames == 100);
	assert(std::abs(w.percentile(.95) - 17.0) < 1e-9);
	assert(std::abs(w.fractionAtLeast(25) - 0.05) < 1e-9);
	w.record(400); assert(w.percentile(1.0) == 400);
	w.reset(); assert(w.frames == 0 && w.percentile(.95) == 0 && w.fractionAtLeast(10) == 0);

	// 120 Hz screen, unlocked: GPU-bound stutter lowers resolution first, never below the floor
	PGSmoothGovernor g; g.configure(0, 120, 550);
	assert(g.limit == 0 && std::abs(g.targetMs() - 1000.0 / 120) < 1e-9 && g.presentInterval() == 0);
	PGSmoothSample heavy = window(14, 0, 0, 12); heavy.lateFraction = 0.5;
	assert(!g.step(heavy));			// one bad window is not enough
	assert(g.step(heavy) && g.scale == 880 && g.limit == 0);
	for (int i = 0; i < 3; i++) assert(!g.step(heavy));	// cooldown after a change
	int guard = 0;
	while (g.scale > g.minScale && guard++ < 100) g.step(heavy);
	assert(g.scale == 550);
	// at the floor, still late: the cap drops 120 -> 60 -> 30 and no further
	guard = 0; while (g.limit != 2 && guard++ < 100) g.step(heavy);
	assert(g.limit == 2 && std::abs(g.presentInterval() - 1.0 / 30) < 1e-9);
	for (int i = 0; i < 50; i++) g.step(heavy);
	assert(g.limit == 2 && g.scale == 550);

	// game-thread bound (low GPU time): the cap drops before resolution
	g.configure(1, 60, 550);
	PGSmoothSample cpu = window(25, 0, 0, 5); cpu.lateFraction = 0.4;
	g.step(cpu); assert(g.step(cpu) && g.limit == 2 && g.scale == 1000);

	// recovery: steady frames with headroom raise resolution back, then the cap, never past the player's
	g.configure(1, 120, 550); g.scale = 700; g.limit = 2;
	// the phone keeps up with whatever cap is set: intervals follow the target, GPU time stays at 6 ms
	auto easy = [&]() { PGSmoothSample s = window(g.targetMs(), 0, 0, 6); s.lateFraction = 0; return s; };
	guard = 0; while ((g.scale < 1000 || g.limit != 1) && guard++ < 500) g.step(easy());
	assert(g.scale == 1000 && g.limit == 1);
	for (int i = 0; i < 100; i++) g.step(easy());
	assert(g.limit == 1);			// player chose 60: never raised to 120
	assert(std::abs(g.presentInterval() - 1.0 / 60) < 1e-9);

	// 60 Hz screen: "off" and "60" are the same rate, the next lower cap is 30
	g.configure(0, 60, 550);
	assert(g.lowerLimit(0) == 2 && g.presentInterval() == 0);

	// heat: serious caps 800 and 60 FPS at once, critical 650 and 30 FPS
	g.configure(0, 120, 550);
	PGSmoothSample fine = window(8.3, 0, 0, 3, 2);
	assert(g.step(fine) && g.scale == 800 && g.limit == 1);
	fine.thermal = 3;
	for (int i = 0; i < 3; i++) g.step(fine);
	assert(g.scale == 650 && g.limit == 2);

	// too few frames (loading, background): no decision
	g.configure(1, 60, 550);
	PGSmoothSample idle = window(16.6, 0, 0, 20, 0, 5); idle.lateFraction = 1;
	for (int i = 0; i < 10; i++) assert(!g.step(idle));
	assert(g.scale == 1000 && g.limit == 1);

	// oscillation: a raise followed by stutter doubles the wait before the next raise
	g.configure(1, 60, 550); g.scale = 900;
	PGSmoothSample ok = window(16.6, 0, 0, 5); ok.lateFraction = 0;
	guard = 0; while (!g.lastWasUp && guard++ < 50) g.step(ok);
	assert(g.lastWasUp && g.scale > 900);
	for (int i = 0; i < 3; i++) g.step(ok);	// cooldown
	PGSmoothSample bad = window(16.6, 0, 0, 15); bad.lateFraction = 0.3;
	g.step(bad);
	assert(g.upHold == PGSmoothGovernor::kBaseUpHold * 2);

	// late fraction from a real window: 1 in 10 frames at 2.5x the target
	PGPresentIntervalWindow lw; for (int i = 0; i < 60; i++) lw.record(i % 10 == 0 ? 41.5 : 16.6);
	assert(std::abs(lw.fractionAtLeast(16.6 * 1.5) - 0.1) < 1e-9);
	(void)withLate;
	puts("PASS: interval window, GPU/CPU-bound steps, floors, player cap, 60/120 Hz, thermal ceilings, idle windows, raise backoff.");
}
